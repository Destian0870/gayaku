# Presentasi: Integrasi Machine Learning pada Smart Scanner

Catatan untuk presentasi ke dosen. Setiap angka di sini bisa dibuktikan lewat
berkas atau perintah yang ditulis di kolom sumbernya — jangan menghafal angka
tanpa bisa menunjukkannya.

---

## 1. Klaim utama (satu slide)

Smart Scanner bukan lagi purwarupa: pemisahan latar, klasifikasi pakaian, dan
pembacaan warna dominan berjalan **di dalam aplikasi (on-device)**. Foto pakaian
tidak pernah dikirim ke server — aplikasi tidak punya klien HTTP dan manifes
rilis tidak meminta izin `INTERNET`.

## 2. Alur pipeline (satu slide diagram)

```
galeri / kamera → matting (U-2-Net small) → Cutout → klasifikasi (MobileNetV3-small)
                → warna dominan (K-Means) → koreksi pengguna → SQLite
```

Klasifikasi dijalankan pada **hasil potongan**, bukan foto mentah: data latih
berupa foto produk berlatar putih, sehingga memotong latar dulu membuat bentuk
yang dilihat model sama dengan bentuk saat latihan (ADR-0005).

## 3. Keputusan dan alasannya (slide yang paling dinilai)

| Keputusan | Alasan | Berkas |
|---|---|---|
| Inferensi di perangkat, bukan server | demo tidak bergantung jaringan; tidak ada citra yang diunggah | `docs/adr/0001` |
| Hanya model berlisensi permisif (Apache/MIT/BSD) | bobot YOLO Ultralytics = AGPL-3.0; SegFormer-clothes = non-komersial NVIDIA; RMBG-2.0 = CC BY-NC; `isnet-general-use` bobotnya tidak pernah dilisensikan (`xuebinqin/DIS#150`) | `docs/adr/0002` |
| Matting `u2netp`, klasifikasi dilatih sendiri | satu-satunya kombinasi yang lolos kebijakan lisensi dan tetap kecil (10,7 MB) | `docs/adr/0002`, `0005` |
| Satu pakaian per foto, tanpa detektor objek | menu latar belakang di `design/scanning_page.png` memperlihatkan satu pakaian; detektor hanya menambah langkah | `docs/adr/0005` |
| Wardrobe disimpan di SQLite dengan id | sebelumnya item dirujuk lewat nama, sehingga mengganti nama menghapus isi kombinasi | `docs/adr/0004` |

Sebutkan juga apa yang **diubah dari proposal**: proposal menulis MediaPipe +
YOLOv8. MediaPipe ImageSegmenter belum punya binding Flutter (issue #48 masih
terbuka sejak 2024), dan bobot YOLOv8 fashion yang paling mudah didapat berlisensi
AGPL-3.0. Bentuk pipeline-nya dipertahankan, modelnya diganti dengan yang boleh
dipakai.

## 4. Data

| Sumber | Isi | Status |
|---|---|---|
| `alexeygrigorev/clothing-dataset-small` (CC0-1.0) | 3.068 / 341 / 372 foto, 10 kelas | dipakai sekarang (model *bootstrap*) |
| Kaggle *Fashion Product Images* | 41.369 dari 44.424 baris masuk ke 80 label terpilih | target akhir (ADR-0003) |

Catatan lisensi yang harus Anda sampaikan lebih dulu: label MIT pada katalog
Kaggle adalah klaim pengunggah atas **label**, bukan atas fotonya (foto katalog
pihak ketiga). Karena itu bobot hasil latihan dan APK-nya adalah artefak
perkuliahan — tidak disebarluaskan dan tidak untuk dijual.

## 5. Pelatihan dan ekspor

Transfer learning `mobilenet_v3_small` pada 224 px, augmentasi flip/rotasi/colour
jitter, 8 epoch CPU, normalisasi ImageNet ditanam di dalam model hasil ekspor.
Alur ekspor: PyTorch → ONNX → TFLite (`onnx2tf`), dijalankan dari
`ml_workspace/bootstrap/`.

Yang menunjukkan rekayasa, bukan sekadar menjalankan skrip: **ekspor diberi
gerbang pemeriksaan**. Konversi ditolak kalau akurasi hasil konversi jatuh, dan
aplikasi memeriksa sendiri saat memuat bahwa bentuk tensor + jumlah kelas cocok —
kalau tidak, muncul pesan kesalahan, bukan tebakan label yang salah satu per satu.

## 6. Hasil

| Metrik | Nilai | Sumber |
|---|---|---|
| Akurasi validasi | 90,9% | `ml_workspace/bootstrap/artifacts/report.md` |
| Akurasi test (held-out) | 91,9% | idem |
| Kesesuaian TFLite vs PyTorch | 179/179 gambar, argmax sama | idem |
| Paritas ONNX vs PyTorch | selisih maks 2,68e-7 | idem |
| Ukuran model di APK | 6,13 MB + 4,58 MB | `flutter_app/assets/models/LICENSES.md` |
| Sapuan 16 foto aset aplikasi | lihat tabelnya | `ml_workspace/artifacts/asset_sweep.md` |
| Uji di perangkat (emulator) | 3 Category berbeda, Cutout bersih | idem |
| Uji otomatis | 54 test lulus; `flutter analyze` tanpa error (3 info deprecation lama) | `flutter_app/test/` |

Angka di perangkat, dari uji nyata: kemeja → **Tops / Kemeja** 100%, sepatu
sneakers → **Shoes / Sepatu** 100%, celana jeans → **Bottoms / Celana Panjang**
91%. Foto yang sama menghasilkan angka yang sama setiap kali dijalankan.

**Latensi per pemindaian belum diukur.** Kalau ditanya, jawab apa adanya:
pengukuran bisa ditambahkan dalam beberapa menit (stopwatch di
`lib/logic/scan_pipeline.dart`, lalu satu kali pindai di perangkat).

## 7. Batasan yang Anda akui lebih dulu

- **Aksesori belum dikenali sebagai aksesori**: model bootstrap belum punya kelas
  tas/jam/kalung, jadi tas kanvas terbaca "Longsleeve 53,7%" dan jam tangan
  "Shoes 66,3%". Katalog Kaggle menambahkan Handbags 1.759, Wallets 928, Watches
  2.542, Sunglasses 1.073.
- **Foto pakaian yang dipakai orang gagal**: rok yang dipakai model membaca
  "Dress 52%" dan potongannya mengambil bagian tubuh, bukan roknya. Kontrak
  pengambilan foto adalah satu pakaian, diletakkan, latar polos.
- **Tidak ada penolakan "ini bukan pakaian"**: tangkapan layar aplikasi sendiri
  pernah terbaca "Shoes 98%". Karena itu baris keyakinan di layar koreksi harus
  dibaca sebagai petunjuk, dan langkah Edit sebagai pengaman.
- **Pakaian satu potong dipetakan ke Tops** (gaun → Tops/Gaun) karena istilah
  domain mengunci lima Category. Menambah Category "Dress" adalah keputusan
  produk, belum diambil.
- **Skor rekomendasi masih berbasis aturan** (harmoni warna 50%, formalitas 30%,
  acara 20%), bukan model yang dilatih — itu modul terpisah dan belum dikerjakan.

## 8. Skenario demo langsung

1. Buka aplikasi → **Scan** → ikon galeri → pilih foto kemeja → tunjukkan Cutout,
   `Category: Tops`, `Nama: Kemeja`, `Terdeteksi: Shirt • 100%`.
2. Tekan **Edit** pada Category, ubah ke `Outerwear` → tunjukkan bahwa koreksi
   pengguna dihargai (ini yang di proposal disebut tahap *Manual Correction*).
3. Simpan → buka **Wardrobe** → item baru muncul dengan gambar hasil potongan.
4. Tutup paksa aplikasi lalu buka lagi → item masih ada (SQLite).
5. Ulangi langkah 1 dengan foto sepatu → `Shoes / Sepatu 100%`.

Siapkan tiga foto uji di galeri sebelum presentasi, dan hindari foto pakaian yang
dipakai orang.

## 9. "Apa yang benar-benar ML di sini?"

Sampaikan sebelum ditanya:

- **Dilatih sendiri**: pengklasifikasi jenis pakaian (bobotnya hasil pelatihan,
  dievaluasi pada data held-out).
- **Model pra-latih yang dipakai apa adanya**: model matting U-2-Net small
  (Apache-2.0, bobotnya ikut dibundel).
- **Bukan ML**: K-Means untuk warna dominan dan skor harmoni warna — algoritma
  klasik, dan itu wajar disebut apa adanya.

## 10. Langkah berikutnya

1. Latih dengan katalog Kaggle → kelas aksesori + pemisahan jeans/trousers.
2. Ambang keyakinan atau penolakan "bukan pakaian".
3. Category `Dress` untuk pakaian satu potong.
4. Baru setelah itu modul rekomendasi (bobot skor, cuaca, preferensi gaya).

## Pertanyaan yang kemungkinan muncul

| Pertanyaan | Jawaban singkat |
|---|---|
| Kenapa tidak YOLOv8/MediaPipe seperti proposal? | lisensi dan belum ada binding Flutter; ADR-0002 mencatat alternatif yang ditolak |
| Ini ML asli atau aturan? | pengklasifikasi dilatih sendiri, matting pra-latih, K-Means algoritma klasik |
| Butuh internet? | tidak; manifes rilis tanpa izin INTERNET |
| Berapa ukuran dan kecepatannya? | 10,7 MB model; latensi belum diukur — sebutkan apa adanya |
| Bagaimana dievaluasi? | split held-out + confusion matrix + sapuan 16 foto aset + uji di perangkat |
| Kenapa aksesori salah? | daftar kelas model bootstrap belum memuatnya; katalog menambahkannya |
| Kenapa gaun jadi Tops? | hanya ada lima Category (CONTEXT.md); menambah Category adalah keputusan produk |
| Bisakah pakai banyak pakaian dalam satu foto? | belum — model matting akan menggabungkan semuanya jadi satu siluet |

## Berkas yang bisa ditunjukkan

- `docs/adr/0001`–`0005` — catatan keputusan beserta alternatif yang ditolak.
- `ml_workspace/bootstrap/artifacts/report.md` — akurasi, confusion matrix,
  riwayat epoch, audit konversi.
- `ml_workspace/artifacts/asset_sweep.md` — perilaku model pada foto milik
  aplikasi sendiri, termasuk kegagalannya.
- `flutter_app/assets/models/LICENSES.md` — lisensi, sha256, dan bentuk tensor
  setiap model yang dibundel.
- `ml_workspace/README.md` — perintah menjalankan ulang seluruh pelatihan.
