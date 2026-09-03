#define TINY_GSM_MODEM_SIM7000
#define TINY_GSM_RX_BUFFER 512

#include <Adafruit_Fingerprint.h>
#include <ArduinoJson.h>
#include <LiquidCrystal_I2C.h>
#include <Wire.h>
#include <RTClib.h>
#include <TinyGsmClient.h>
#include <avr/wdt.h>

#define SerialMon   Serial
#define SerialFP    Serial1
#define SerialGSM   Serial2

Adafruit_Fingerprint finger(&SerialFP);
LiquidCrystal_I2C    lcd(0x27, 16, 2);
RTC_DS3231           rtc;
TinyGsm              modem(SerialGSM);
TinyGsmClient        gsmClient(modem);

#define RELAY_PIN       52
#define BUZZER_PIN      46
#define BUTTON_PIN      48
#define POWER_LED_PIN   A4

const char APN[]       = "nb1internet";
const char GPRS_USER[] = "";
const char GPRS_PASS[] = "";

const char* SERVER_HOST = "";
const int   SERVER_PORT = ;

const unsigned long RELAY_DURATION_MS   = 5000UL;
const unsigned long POLL_INTERVAL_MS    = 3000UL;
const unsigned long SIGNAL_INTERVAL_MS  = 60000UL;
const unsigned long LCD_RESET_DELAY_MS  = 3000UL;
const unsigned long MODEM_INIT_DELAY_MS = 3000UL;
const unsigned long LCD_INFO_SHOW_MS    = 2000UL;
const unsigned long HTTP_WAIT_MS        = 12000UL;  // timeout tunggu respons HTTP
const unsigned long HTTP_READ_MS        = 5000UL;   // timeout baca body HTTP
const unsigned long AT_CMD_GAP_MS       = 100UL;    // jeda antar AT command

const char* jsonData =
    "[{\"ID\":1,\"Nama\":\"Ferdi\"},"
     "{\"ID\":2,\"Nama\":\"Sambo\"}]";

unsigned long relayOffTime       = 0;
bool          relayActionPending = false;
int           lastButtonState    = HIGH;
int           lastFingerprintID  = -99;
unsigned long lcdResetTime       = 0;
bool          lcdNeedReset       = false;
unsigned long lastSignalCheck    = 0;
unsigned long lastPollCheck      = 0;
bool          gprsReady          = false;
bool          fingerprintAktif   = false;

// Suspend WDT → jalankan kode blocking → resume WDT
// Dipakai khusus untuk TinyGSM blocking call
inline void wdtReset() { wdt_reset(); }

// Matikan WDT sementara (untuk blocking call TinyGSM)
inline void wdtSuspend() { wdt_disable(); }

// Nyalakan kembali WDT 
inline void wdtResume()  {
    wdt_reset();
    wdt_enable(WDTO_8S);
}

// ============================================================
String getDateTime() {
    DateTime now = rtc.now();
    char buf[22];
    sprintf(buf, "%04d-%02d-%02dT%02d:%02d:%02d",
            now.year(), now.month(), now.day(),
            now.hour(), now.minute(), now.second());
    return String(buf);
}

// AT COMMAND
// Setiap AT command < 8 detik → aman dengan WDT aktif
// wdtReset() per iterasi baca untuk loop timeout
String sendAT(const String& cmd, unsigned long timeout = 2000) {
    // Flush buffer
    while (SerialGSM.available()) SerialGSM.read();
    SerialGSM.println(cmd);

    String res = "";
    unsigned long t = millis();
    while (millis() - t < timeout) {
        while (SerialGSM.available()) {
            res += (char)SerialGSM.read();
        }
        wdtReset();   // reset WDT tiap iterasi, bukan tiap byte
    }
    SerialMon.print("[AT] "); SerialMon.print(cmd);
    SerialMon.print(" -> "); SerialMon.println(res);
    return res;
}

// INIT NB-IoT
// wdtReset() sebelum SETIAP perintah untuk jaga jarak antar call
bool initNBIoT() {
    SerialMon.println("=== Init Modem ===");
    wdtReset(); sendAT("AT",           1000);
    wdtReset(); sendAT("AT+COPS=0",    5000); 
    wdtReset(); sendAT("AT+CNMP=2",    3000);
    wdtReset(); sendAT("AT+CMNB=3",    3000);
    wdtReset(); sendAT("AT+CGNSPWR=1", 3000);
    wdtReset(); sendAT("AT+CDNSCFG=\"8.8.8.8\",\"8.8.4.4\"", 2000);   // <-- BARIS BARU
    wdtReset(); SerialMon.println(sendAT("AT+COPS?",  2000));
    wdtReset(); SerialMon.println(sendAT("AT+CREG?",  2000));
    wdtReset(); SerialMon.println(sendAT("AT+CGREG?", 2000));
    wdtReset();
    SerialMon.println("=== Init selesai ===");
    return true;
}
// HTTP GET
//   wdtSuspend → connect (blocking, tak bisa di-patch)
//   wdtResume  → loop tunggu + baca dengan wdtReset per iterasi
// connect() TinyGSM bisa >8 detik jika network lambat 
// suspend WDT selama connect, lalu resume setelahnya.
String httpGET(const String& path) {
    // connect() bisa blocking lama → suspend WDT 
    wdtSuspend();
    bool connected = gsmClient.connect(SERVER_HOST, SERVER_PORT);
    wdtResume();

    if (!connected) {
        SerialMon.println("Gagal konek: " + String(SERVER_HOST));
        return "";
    }

    gsmClient.print("GET " + path + " HTTP/1.1\r\n");
    gsmClient.print("Host: doorlockku.my.id\r\n");
    gsmClient.print("Connection: close\r\n\r\n");

    // Tunggu ada data — max HTTP_WAIT_MS, wdtReset per 10ms
    unsigned long t = millis();
    while (!gsmClient.available() && millis() - t < HTTP_WAIT_MS) {
        wdtReset();
    }

    if (!gsmClient.available()) {
        SerialMon.println("Timeout respons server");
        gsmClient.stop();
        return "";
    }

    // Baca respons — max HTTP_READ_MS, wdtReset per byte
    String response = "";
    t = millis();
    while (gsmClient.connected() || gsmClient.available()) {
        while (gsmClient.available()) {
            response += (char)gsmClient.read();
            wdtReset();
        }
        if (millis() - t >= HTTP_READ_MS) break;
        wdtReset();
    }
    gsmClient.stop();

    // Ambil body setelah header
    int bodyStart = response.indexOf("\r\n\r\n");
    if (bodyStart >= 0) {
        String body = response.substring(bodyStart + 4);
        body.trim();
        SerialMon.println("GET " + path + " -> " + body);
        return body;
    }
    return "";
}

void tampilAwal() {
    lcd.clear();
    lcd.setCursor(0, 0); lcd.print("Fingerprint ON");
    lcd.setCursor(0, 1); lcd.print("Silahkan Scan");
}

void tampilStandby() {
    lcd.clear();
    lcd.setCursor(0, 0); lcd.print("Fingerprint OFF");
    lcd.setCursor(0, 1); lcd.print("Tunggu Perintah");
}

void tampilConnecting() {
    lcd.clear();
    lcd.setCursor(0, 0); lcd.print("Inisialisasi");
    lcd.setCursor(0, 1); lcd.print("sistem!!");
}

void setLCDReset() {
    lcdResetTime = millis();
    lcdNeedReset = true;
}
void beep(int times) {
    for (int i = 0; i < times; i++) {
        digitalWrite(BUZZER_PIN, HIGH); delay(100);
        digitalWrite(BUZZER_PIN, LOW);  delay(100);
    }
}

int getFingerprintID() {
    uint8_t p = finger.getImage();
    if (p == FINGERPRINT_NOFINGER) return -2;
    if (p != FINGERPRINT_OK)       return -1;
    p = finger.image2Tz();
    if (p != FINGERPRINT_OK) return -1;
    p = finger.fingerSearch();
    if (p == FINGERPRINT_NOTFOUND) return 0;
    if (p != FINGERPRINT_OK)       return -1;
    return finger.fingerID;
}

// ENSURE GPRS
// waitForNetwork() dan gprsConnect() adalah blocking call
// TinyGSM yang TIDAK bisa di-interupsi.
// Jadi: suspend WDT sebelum, resume setelah.
bool ensureGprs() {
    if (!modem.isNetworkConnected()) {
        SerialMon.println("Reconnect network...");
        lcd.clear();
        lcd.setCursor(0, 0); lcd.print("Cari Jaringan");
        lcd.setCursor(0, 1); lcd.print("NB-IoT...");

        // waitForNetwork bisa sampai 60 detik → WAJIB suspend WDT
        wdtSuspend();
        bool netOk = modem.waitForNetwork(30000);
        wdtResume();

        if (!netOk) {
            SerialMon.println("Gagal network");
            return false;
        }
        SerialMon.println("Network OK");
    }

    if (!modem.isGprsConnected()) {
        SerialMon.println("Connect NB-IoT data...");

        wdtSuspend();
        bool gprsOk = modem.gprsConnect(APN, GPRS_USER, GPRS_PASS);
        wdtResume();

        if (!gprsOk) {
            SerialMon.println("Gagal GPRS connect");
            return false;
        }
        SerialMon.println("GPRS OK");
    }

    return true;
}

bool          modemRestarting  = false;
unsigned long modemRestartTime = 0;

enum RestartStep { RS_IDLE, RS_RESTART, RS_WAIT_SERIAL, RS_NBIOT, RS_WAIT_POST, RS_DONE };
RestartStep restartStep = RS_IDLE;

void startModemRestart() {
    if (modemRestarting) return;
    modemRestarting  = true;
    restartStep      = RS_IDLE;
    modemRestartTime = millis();
    gprsReady        = false;
    SerialMon.println("Jadwal restart modem...");
}

// Kembalikan true jika restart SELESAI
bool modemRestartUpdate() {
    if (!modemRestarting) return false;
    unsigned long now = millis();

    switch (restartStep) {
        case RS_IDLE:
            SerialMon.println("Restart modem...");
            // modem.restart() bisa lama → suspend WDT
            wdtSuspend();
            modem.restart();
            wdtResume();
            modemRestartTime = millis();
            restartStep      = RS_WAIT_SERIAL;
            return false;

        case RS_WAIT_SERIAL:
            // Tunggu 8 detik pasca restart — non-blocking
            if (now - modemRestartTime >= 8000UL) {
                SerialGSM.begin(115200);
                modemRestartTime = millis();
                restartStep      = RS_NBIOT;
            }
            return false;

        case RS_NBIOT:
            // Tunggu 2 detik setelah serial siap — non-blocking
            if (now - modemRestartTime >= 2000UL) {
                initNBIoT();
                modemRestartTime = millis();
                restartStep      = RS_WAIT_POST;
            }
            return false;

        case RS_WAIT_POST:
            // Tunggu 5 detik setelah initNBIoT — non-blocking
            if (now - modemRestartTime >= 5000UL) {
                if (ensureGprs()) {          // coba connect ulang GPRS
                gprsReady = true;
                }
                modemRestarting = false;
                restartStep     = RS_DONE;
                SerialMon.println("Modem restart selesai");
                return true;
            }
            return false;

        default:
            modemRestarting = false;
            return true;
    }
}

void taskSignalGprs() {
    if (modemRestarting) return;
    if (!modem.isNetworkConnected()) {
        gprsReady = false;
        SerialMon.println("Signal hilang");
        return;
    }
    gprsReady = modem.isGprsConnected();
    if (!gprsReady) {
        gprsReady = ensureGprs();
        if (!gprsReady) startModemRestart();
    }
}

void kirimGps() {
    SerialMon.println("Ambil GPS...");
    wdtReset();
    String res = sendAT("AT+CGNSINF", 2000);
    String lat = "0", lng = "0";

    if (res.indexOf("+CGNSINF:") >= 0) {
        int p1  = res.indexOf(",");
        int p2  = res.indexOf(",", p1 + 1);
        int fix = res.substring(p1 + 1, p2).toInt();
        if (fix == 1) {
            int latStart = res.indexOf(",", p2 + 1) + 1;
            int latEnd   = res.indexOf(",", latStart);
            lat = res.substring(latStart, latEnd);
            int lonStart = latEnd + 1;
            int lonEnd   = res.indexOf(",", lonStart);
            lng = res.substring(lonStart, lonEnd);
            SerialMon.print("LAT: "); SerialMon.println(lat);
            SerialMon.print("LNG: "); SerialMon.println(lng);
        } else {
            SerialMon.println("GPS belum FIX");
        }
    }

    wdtReset();
    String body = httpGET("/update_location.php?lat=" + lat + "&lng=" + lng);
    wdtReset();

    if (body.indexOf("ok") >= 0 || body.indexOf("OK") >= 0) {
        httpGET("/reset_location.php");
        SerialMon.println("Lokasi terkirim");
        // lcd.clear();
        // lcd.setCursor(0, 0); lcd.print("Lokasi Terkirim");
        // lcd.setCursor(0, 1); lcd.print(lat.substring(0, 8));
        // setLCDReset();
    } else {
        SerialMon.println("Gagal kirim lokasi");
    }
    wdtReset();
}

void simpanLog(int idJari, String namaJari, bool berhasil) {
    String waktu = getDateTime();
    namaJari.replace(" ", "+");
    String path = "/insert_log.php?"
                  "id_jari="    + String(idJari) +
                  "&nama_jari=" + namaJari +
                  "&berhasil="  + String(berhasil ? 1 : 0) +
                  "&waktu_rtc=" + waktu;
    wdtReset();
    String body = httpGET(path);
    wdtReset();
    SerialMon.println(body.indexOf("ok") >= 0 || body.indexOf("OK") >= 0
                      ? "Log tersimpan" : "Gagal simpan log");
}

// ============================================================
// TASK: POLLING SERVER
// ============================================================
void taskPollServer() {
    if (!gprsReady || modemRestarting) {
        SerialMon.println("Poll skip: tidak ready");
        wdtReset();
        return;
    }
    if (!modem.isGprsConnected()) {
        gprsReady = false;
        startModemRestart();
        return;
    }

    wdtReset();
    String body = httpGET("/get_command.php");
    wdtReset();

    if (body.length() == 0 || body.indexOf("fingerprint") < 0) {
        SerialMon.println("Gagal baca perintah");
        return;
    }

    bool fpBaru      = body.indexOf("\"fingerprint\":true")  >= 0;
    bool mintaLokasi = body.indexOf("\"minta_lokasi\":true") >= 0;

    SerialMon.print("fingerprint  : "); SerialMon.println(fpBaru);
    SerialMon.print("minta_lokasi : "); SerialMon.println(mintaLokasi);

    if (mintaLokasi) kirimGps();

    if (fpBaru != fingerprintAktif) {
        fingerprintAktif = fpBaru;
        if (fingerprintAktif) {
            SerialMon.println(">> Fingerprint ON");
            tampilAwal();
            finger.LEDcontrol(FINGERPRINT_LED_ON, 0, FINGERPRINT_LED_PURPLE);
        } else {
            SerialMon.println(">> Fingerprint OFF");
            tampilStandby();
            finger.LEDcontrol(FINGERPRINT_LED_OFF, 0, FINGERPRINT_LED_PURPLE);
        }
    }
}

enum SetupPhase {
    SP_START = 0,
    SP_MODEM_SERIAL_WAIT,   // tunggu serial GSM stabil  (millis, 3 detik)
    SP_NBIOT_INIT,          // jalankan initNBIoT()
    SP_NETWORK_WAIT,        // waitForNetwork — suspend WDT di ensureGprs
    SP_GPRS_CONNECT,        // gprsConnect    — suspend WDT di ensureGprs
    SP_LCD_IP_SHOW,         // tampil IP      (millis, 2 detik)
    SP_SERVER_TEST,         // httpGET test
    SP_DONE
};

SetupPhase    setupPhase      = SP_START;
unsigned long setupPhaseTimer = 0;
bool          setupComplete   = false;

void setupUpdate() {
    if (setupComplete) return;
    unsigned long now = millis();
    wdtReset();

    switch (setupPhase) {

        // ── Tunggu 3 detik agar GSM Serial stabil ──
        case SP_START:
            setupPhaseTimer = now;
            setupPhase      = SP_MODEM_SERIAL_WAIT;
            return;

        case SP_MODEM_SERIAL_WAIT:
            if (now - setupPhaseTimer >= MODEM_INIT_DELAY_MS) {
                setupPhase = SP_NBIOT_INIT;
            }
            return;

        // ── Init AT command NB-IoT (~21 detik, WDT reset tiap AT) ──
        case SP_NBIOT_INIT:
            lcd.clear();
            lcd.setCursor(0, 0); lcd.print("Daftar NB-IoT");
            lcd.setCursor(0, 1); lcd.print("Mohon Tunggu...");
            initNBIoT();   // wdtReset() sudah di dalam setiap sendAT()
            wdtReset();
            SerialMon.println("Tunggu Network...");
            setupPhase = SP_NETWORK_WAIT;
            return;

        // ── waitForNetwork — blocking TinyGSM, suspend WDT ──
        case SP_NETWORK_WAIT: {
            SerialMon.println("waitForNetwork...");
            lcd.clear();
            lcd.setCursor(0, 0); lcd.print("Cari Jaringan");
            lcd.setCursor(0, 1); lcd.print("...");

            // Suspend WDT karena ini bisa sampai 60 detik
            wdtSuspend();
            bool netOk = modem.waitForNetwork(60000);
            wdtResume();

            if (netOk) {
                SerialMon.println("Network OK");
                wdtReset();
                String netMode = sendAT("AT+CMNB?", 1000);
                SerialMon.println("Mode: " + netMode);
                setupPhase = SP_GPRS_CONNECT;
            } else {
                SerialMon.println("Network gagal, mode offline");
                lcd.clear();
                lcd.setCursor(0, 0); lcd.print("NB-IoT Gagal");
                // lcd.setCursor(0, 1); lcd.print("Mode Offline");
                setupPhase = SP_DONE;
            }
            return;
        }

        // ── gprsConnect — blocking TinyGSM, suspend WDT ──
        case SP_GPRS_CONNECT: {
            SerialMon.println("GPRS Connect...");
            lcd.clear();
            lcd.setCursor(0, 0); lcd.print("Koneksi Data");
            lcd.setCursor(0, 1); lcd.print("NB-IoT...");

            // Suspend WDT karena gprsConnect bisa >8 detik
            wdtSuspend();
            bool gprsOk = modem.gprsConnect(APN, GPRS_USER, GPRS_PASS);
            wdtResume();

            if (gprsOk) {
                gprsReady = true;
                SerialMon.print("NB-IoT OK - IP: ");
                SerialMon.println(modem.localIP());
                lcd.clear();
                lcd.setCursor(0, 0); lcd.print("NB-IoT OK");
                lcd.setCursor(0, 1); lcd.print(modem.localIP());
                setupPhaseTimer = millis();   // pakai millis() terbaru
                setupPhase      = SP_LCD_IP_SHOW;
            } else {
                SerialMon.println("GPRS gagal, mode offline");
                lcd.clear();
                lcd.setCursor(0, 0); lcd.print("Data Gagal");
                // lcd.setCursor(0, 1); lcd.print("Mode Offline");
                setupPhase = SP_DONE;
            }
            return;
        }

        // ── Tampil IP 2 detik, millis() non-blocking ──
        case SP_LCD_IP_SHOW:
            if (millis() - setupPhaseTimer >= LCD_INFO_SHOW_MS) {
                setupPhase = SP_SERVER_TEST;
            }
            return;

        // ── Test HTTP ke server ──
        case SP_SERVER_TEST: {
            wdtReset();
            String test = httpGET("/get_command.php");
            wdtReset();
            SerialMon.println(test.indexOf("fingerprint") >= 0
                              ? "SERVER OK" : "SERVER GAGAL / offline");
            setupPhase = SP_DONE;
            return;
        }

        case SP_DONE:
            tampilStandby();
            beep(1);
            SerialMon.println("=== Setup selesai ===");
            setupComplete = true;
            return;
    }
}

void testDNS() {
    wdtReset();
    String res = sendAT("AT+CDNSGIP=\"doorlockku.my.id\"", 8000);
    SerialMon.println("HASIL DNS TEST: " + res);
}

void setup() {
    // Matikan WDT dulu — hardware init bisa lama
    wdt_disable();

    SerialMon.begin(115200);

    pinMode(POWER_LED_PIN, OUTPUT);
    pinMode(BUZZER_PIN,    OUTPUT);
    pinMode(RELAY_PIN,     OUTPUT);
    pinMode(BUTTON_PIN,    INPUT_PULLUP);

    digitalWrite(POWER_LED_PIN, HIGH);
    digitalWrite(RELAY_PIN,     HIGH);   // Relay normally HIGH = terkunci

    lcd.init();
    lcd.backlight();
    tampilConnecting();

    SerialMon.println("Inisialisasi Sistem!!!");

    // RTC
    if (!rtc.begin()) {
        SerialMon.println("ERROR: RTC tidak ditemukan!");
        lcd.clear(); lcd.print("RTC Error!");
        while (1);
    }
    rtc.adjust(DateTime(F(__DATE__), F(__TIME__)));  // uncomment saat pertama upload
    SerialMon.println("RTC OK: " + getDateTime());

    // Fingerprint
    SerialFP.begin(57600);
    finger.begin(57600);
    if (!finger.verifyPassword()) {
        SerialMon.println("ERROR: Fingerprint tidak ditemukan!");
        lcd.clear(); lcd.print("FP Error!");
        while (1);
    }
    finger.getTemplateCount();
    SerialMon.print("Template FP: "); SerialMon.println(finger.templateCount);
    SerialMon.println("Fingerprint OK");

    // GSM Serial
    SerialMon.println("Init GSM Serial...");
    SerialGSM.begin(115200);

    // Aktifkan WDT 8 detik setelah hardware init selesai.
    // Selanjutnya setiap blocking TinyGSM call wajib suspend/resume.
    wdt_enable(WDTO_8S);

    SerialMon.println("=== Mulai Test DNS ===");
    testDNS();   // <-- INI BARIS BARU

    setupPhase = SP_START;
}

// ============================================================
// LOOP — tidak ada delay() sama sekali
// ============================================================
void loop() {
    unsigned long now = millis();

    wdtReset();

    // ── Setup state machine (sampai selesai) ──
    if (!setupComplete) {
        setupUpdate();
        return;
    }

    // ── Modem restart (non-blocking) ──
    if (modemRestarting) {
        modemRestartUpdate();
        return; 
    }

    // ── 1. TOMBOL MANUAL ──
    int buttonState = digitalRead(BUTTON_PIN);
    if (buttonState == LOW && lastButtonState == HIGH) {
        SerialMon.println("Manual Unlock: " + getDateTime());

        lcd.clear();
        lcd.setCursor(0, 0); lcd.print("Manual Unlock");
        lcd.setCursor(0, 1); lcd.print(getDateTime().substring(11));
        digitalWrite(RELAY_PIN, LOW);
        beep(1);
        relayOffTime       = now;
        relayActionPending = true;
        setLCDReset();
    }
    lastButtonState = buttonState;

    // ── 2. AUTO TUTUP RELAY (millis, non-blocking) ──
    if (relayActionPending && (now - relayOffTime >= RELAY_DURATION_MS)) {
        digitalWrite(RELAY_PIN, HIGH);
        SerialMon.println("Relay ditutup otomatis");
        relayActionPending = false;
        lcd.clear();
        lcd.setCursor(0, 0); lcd.print("Terkunci Kembali");
        setLCDReset();
    }

    // ── 3. FINGERPRINT ──
    if (fingerprintAktif) {
        int id = getFingerprintID();

        if (id > 0 && id != lastFingerprintID) {
            SerialMon.print("ID valid: "); SerialMon.println(id);

            StaticJsonDocument<512> doc;
            deserializeJson(doc, jsonData);
            JsonArray array = doc.as<JsonArray>();
            bool found = false;

            for (JsonObject obj : array) {
                if (obj["ID"] == id) {
                    String nama    = obj["Nama"].as<String>();
                    SerialMon.println("Nama   : " + nama);
                    SerialMon.println("Waktu  : " + getDateTime());
                    lcd.clear();
                    lcd.setCursor(0, 0); lcd.print("Akses Diterima");
                    lcd.setCursor(0, 1); lcd.print(nama);
                    digitalWrite(RELAY_PIN, LOW);
                    beep(2);
                    relayOffTime       = now;
                    relayActionPending = true;
                    simpanLog(id, nama, true);
                    found = true;
                    break;
                }
            }

            if (!found) {
                SerialMon.println("Tidak terdaftar");
                lcd.clear();
                lcd.setCursor(0, 0); lcd.print("Akses Ditolak");
                lcd.setCursor(0, 1); lcd.print("Tdk Terdaftar");
                beep(3);
                simpanLog(id, "Unknown", false);
            }

            lastFingerprintID = id;
            setLCDReset();

        } else if (id == 0 && lastFingerprintID != 0) {
            SerialMon.println("Jari tidak dikenal");
            lcd.clear();
            lcd.setCursor(0, 0); lcd.print("Akses Ditolak");
            lcd.setCursor(0, 1); lcd.print("Tdk Dikenal");
            beep(3);
            simpanLog(0, "Unknown", false);
            lastFingerprintID = 0;
            setLCDReset();

        } else if (id == -2) {
            lastFingerprintID = -99;   // tidak ada jari, reset tracker
        }
    }
    

    // ── 4. RESET LCD (millis, non-blocking) ──
    if (lcdNeedReset && (now - lcdResetTime >= LCD_RESET_DELAY_MS)) {
        fingerprintAktif ? tampilAwal() : tampilStandby();
        lcdNeedReset = false;
    }

    // ── 5. CEK SIGNAL + GPRS (setiap 60 detik) ──
    if (now - lastSignalCheck >= SIGNAL_INTERVAL_MS) {
        lastSignalCheck = now;
        taskSignalGprs();
    }

    // ── 6. POLLING SERVER (setiap 3 detik) ──
    if (now - lastPollCheck >= POLL_INTERVAL_MS) {
        lastPollCheck = now;
        taskPollServer();
    }
}
