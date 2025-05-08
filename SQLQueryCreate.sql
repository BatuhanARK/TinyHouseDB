CREATE TABLE Kullanicilar (
    KullaniciID INT PRIMARY KEY IDENTITY(1,1),
    Ad NVARCHAR(20) NOT NULL CHECK (Ad NOT LIKE '%[^a-zA-ZığüşöçİĞÜŞÖÇ ]%'),
    Soyad NVARCHAR(20) NOT NULL CHECK (Soyad NOT LIKE '%[^a-zA-ZığüşöçİĞÜŞÖÇ ]%'),
    Email NVARCHAR(20) UNIQUE NOT NULL CHECK (Email LIKE '%@%.%'),
    Sifre NVARCHAR(20) NOT NULL CHECK (Sifre NOT LIKE '%[<>'';--]%'),
    Rol TINYINT NOT NULL CHECK (Rol IN (0, 1, 2)), -- 0 admin 1 evsahibi 2 kiraci
    Aktif BIT NOT NULL DEFAULT 1 CHECK (Aktif IN (0, 1)),
    KayitTarihi DATETIME DEFAULT GETDATE()
);
CREATE TABLE Evler (
    EvID INT PRIMARY KEY IDENTITY(1,1),
    SahipID INT NOT NULL FOREIGN KEY REFERENCES Kullanicilar(KullaniciID),
    Baslik NVARCHAR(50) NOT NULL CHECK (Baslik NOT LIKE '%[<>'';--@!#$%^&*()]%'), -- tehlikeli karakter engeli
    Aciklama NVARCHAR(200) NOT NULL CHECK (Aciklama NOT LIKE '%[<>'';--@#$%^*()]%'), -- açıklamada da filtre
    Fiyat DECIMAL(10,2) NOT NULL CHECK (Fiyat > 0), -- negatif fiyat engeli
    Konum NVARCHAR(50) NOT NULL CHECK (Konum NOT LIKE '%[<>'';--@#$%^*()]%'), -- konumda da özel karakter engeli
    FotoUrl NVARCHAR(MAX) NULL CHECK (FotoUrl IS NULL OR (FotoUrl LIKE '[%' AND FotoUrl LIKE '%]' AND FotoUrl NOT LIKE '%[<>'';--@#$%^*()]%')), -- JSON'da geçerli olmayan karakterlerin engellenmesi
    Aktif BIT NOT NULL DEFAULT 1 CHECK (Aktif IN (0, 1)),
    EklenmeTarihi DATETIME DEFAULT GETDATE()
);
CREATE TABLE Rezervasyonlar (
    RezervasyonID INT PRIMARY KEY IDENTITY(1,1),
    KiraciID INT FOREIGN KEY REFERENCES Kullanicilar(KullaniciID),
    EvID INT FOREIGN KEY REFERENCES Evler(EvID),
    BaslangicTarihi DATE CHECK (BaslangicTarihi >= GETDATE()), -- Başlangıç tarihi, bugünden önce olamaz
    BitisTarihi DATE,
    Aktif BIT NOT NULL DEFAULT 1 CHECK (Aktif IN (0, 1)),
    RezervasyonTarihi DATETIME DEFAULT GETDATE(),
);
CREATE TABLE Odemeler (
    OdemeID INT PRIMARY KEY IDENTITY(1,1), -- OdemeID: Birincil anahtar
    RezervasyonID INT NOT NULL FOREIGN KEY REFERENCES Rezervasyonlar(RezervasyonID), -- RezervasyonID: Yabancı anahtar
    Tutar DECIMAL(10,2) NOT NULL CHECK (Tutar > 0), -- Tutar: Negatif ödeme engeli
    OdemeTarihi DATETIME DEFAULT GETDATE(), -- OdemeTarihi: Ödeme tarihi
    OdemeDurumu TINYINT NOT NULL CHECK (OdemeDurumu IN (0, 1, 2)), -- 0: Bekliyor, 1: Odendi, 2: Iptal
    Aktif BIT NOT NULL DEFAULT 1 CHECK (Aktif IN (0, 1)) -- Aktif: Yorumun aktifliğini belirler
);
CREATE TABLE Yorumlar (
    YorumID INT PRIMARY KEY IDENTITY(1,1),
    EvID INT NOT NULL FOREIGN KEY REFERENCES Evler(EvID),
    KullaniciID INT NOT NULL FOREIGN KEY REFERENCES Kullanicilar(KullaniciID),
    Puan INT NOT NULL CHECK (Puan >= 1 AND Puan <= 5), -- Sadece 1-5 arası puan
    Yorum NVARCHAR(MAX) NOT NULL CHECK (Yorum NOT LIKE '%[<>'';--@#$%^*()]%'), -- Zararlı karakter engeli
    YorumTarihi DATETIME DEFAULT GETDATE(),
    Aktif BIT NOT NULL DEFAULT 1 CHECK (Aktif IN (0, 1)) -- Sadece 0 ve 1 değeri
);

CREATE TRIGGER TR_ValidateRezervasyonTarihi
ON Rezervasyonlar
AFTER INSERT, UPDATE
AS
BEGIN
    IF EXISTS (
        SELECT 1
        FROM Inserted
        WHERE BitisTarihi <= BaslangicTarihi
    )
    BEGIN
        RAISERROR ('BitisTarihi, BaslangicTarihi''nden sonra olmalıdır.', 16, 1);
        ROLLBACK TRANSACTION;
    END
END;
CREATE TRIGGER TR_UpdateEvAktifToPasif
ON Rezervasyonlar
FOR INSERT
AS
BEGIN
    DECLARE @EvID INT;
    -- Inserted tablosundan ev ID'si alınır
    SELECT @EvID = EvID
    FROM INSERTED;
    -- İlgili evin aktif durumunu pasif (0) yap
    UPDATE Evler
    SET Aktif = 0  -- Ev artık rezerve edilmiş ve pasif olacak
    WHERE EvID = @EvID;
END;
CREATE TRIGGER TR_EvlerInsertEvSahibiKontrol
ON Evler
INSTEAD OF INSERT
AS
BEGIN
    IF EXISTS (
        SELECT 1
        FROM inserted i
        JOIN Kullanicilar k ON i.SahipID = k.KullaniciID
        WHERE k.Rol != 1
    )
    BEGIN
        RAISERROR ('Sadece rolü 1 (Ev Sahibi) olan kullanıcılar ev ekleyebilir.', 16, 1);
        ROLLBACK;
        RETURN;
    END
    -- Rol doğruysa veriyi ekle
    INSERT INTO Evler (SahipID, Baslik, Aciklama, Fiyat, Konum, FotoUrl, Aktif, EklenmeTarihi)
    SELECT SahipID, Baslik, Aciklama, Fiyat, Konum, FotoUrl, Aktif, EklenmeTarihi
    FROM inserted;
END;
CREATE TRIGGER TR_KiraciKontrol
ON Rezervasyonlar
INSTEAD OF INSERT
AS
BEGIN
    -- Kiracı kontrolü
    IF EXISTS (
        SELECT 1
        FROM inserted i
        JOIN Kullanicilar k ON i.KiraciID = k.KullaniciID
        WHERE k.Rol != 2
    )
    BEGIN
        RAISERROR ('Sadece rolü 2 (Kiracı) olan kullanıcılar rezervasyon yapabilir.', 16, 1);
        ROLLBACK;
        RETURN;
    END;
    -- Eğer geçerliyse, geçici tabloya yaz
    INSERT INTO Rezervasyonlar (KiraciID, EvID, BaslangicTarihi, BitisTarihi)
    SELECT KiraciID, EvID, BaslangicTarihi, BitisTarihi
    FROM inserted;
END;
CREATE TRIGGER TR_TarihCakismasiKontrol
ON Rezervasyonlar
AFTER INSERT
AS
BEGIN
    -- Tarih çakışması kontrolü
    IF EXISTS (
        SELECT 1
        FROM inserted i
        JOIN Rezervasyonlar r ON i.EvID = r.EvID
        WHERE
            i.BaslangicTarihi < r.BitisTarihi AND
            i.BitisTarihi > r.BaslangicTarihi
            AND i.RezervasyonID != r.RezervasyonID
    )
    BEGIN
        RAISERROR ('Seçilen tarihlerde bu ev için zaten bir rezervasyon bulunmaktadır.', 16, 1);
        ROLLBACK;
        RETURN;
    END;
END;
CREATE TRIGGER TR_OdemeTutariHesapla
ON Odemeler
AFTER INSERT
AS
BEGIN
    UPDATE o
    SET Tutar = ROUND(e.Fiyat * 1.03, 2)
    FROM Odemeler o
    JOIN inserted i ON o.OdemeID = i.OdemeID
    JOIN Rezervasyonlar r ON i.RezervasyonID = r.RezervasyonID
    JOIN Evler e ON r.EvID = e.EvID;
END;
CREATE TRIGGER TR_OdemeTarihi_Kontrol
ON Odemeler
AFTER INSERT, UPDATE
AS
BEGIN
    -- Sadece OdemeDurumu = 1 olanlara tarih ata
    UPDATE o
    SET OdemeTarihi = GETDATE()
    FROM Odemeler o
    INNER JOIN inserted i ON o.OdemeID = i.OdemeID
    WHERE i.OdemeDurumu = 1;
    -- OdemeDurumu 1 değilse tarih NULL olsun
    UPDATE o
    SET OdemeTarihi = NULL
    FROM Odemeler o
    INNER JOIN inserted i ON o.OdemeID = i.OdemeID
    WHERE i.OdemeDurumu IN (0, 2);
END;
CREATE TRIGGER TR_YorumOdemeKontrol
ON Yorumlar
INSTEAD OF INSERT
AS
BEGIN
    DECLARE @KullaniciID INT;
    DECLARE @EvID INT;

    -- inserted tablosundan verileri alalım
    SELECT @KullaniciID = KullaniciID, @EvID = EvID FROM inserted;

    -- Evde ödemesi tamamlanmış rezervasyonu olup olmadığı kontrol ediliyor
    IF NOT EXISTS (
        SELECT 1
        FROM Rezervasyonlar r
        INNER JOIN Odemeler o ON r.RezervasyonID = o.RezervasyonID
        WHERE r.EvID = @EvID
          AND r.KiraciID = @KullaniciID
          AND o.OdemeDurumu = 1 -- OdemeDurumu = 1 (ödendi)
    )
    BEGIN
        RAISERROR('Bu evde ödemesi tamamlanmış bir rezervasyonunuz yok.', 16, 1);
        RETURN;
    END

    -- Eğer kontrol geçerse, insert işlemi yapılır
    INSERT INTO Yorumlar (EvID, KullaniciID, Puan, Yorum)
    SELECT EvID, KullaniciID, Puan, Yorum FROM inserted;
END;

CREATE PROCEDURE SP_YorumlariGetir
    @EvID INT
AS
BEGIN
    SELECT y.YorumID, y.Puan, y.Yorum, k.Ad, k.Soyad, y.KullaniciID
    FROM Yorumlar y
    INNER JOIN Kullanicilar k ON y.KullaniciID = k.KullaniciID
    WHERE y.EvID = @EvID;
END;
CREATE PROCEDURE SP_YeniKullaniciEkle
    @Ad NVARCHAR(20),
    @Soyad NVARCHAR(20),
	@Email NVARCHAR(20),
    @Sifre NVARCHAR(20),
    @Rol TINYINT
AS
BEGIN
    INSERT INTO Kullanicilar (Ad, Soyad, Email, Sifre, Rol)
    VALUES (@Ad, @Soyad, @Email, @Sifre, @Rol);
END;

CREATE FUNCTION FN_EvOrtalamaPuan (@EvID INT)
RETURNS DECIMAL(3,2)
AS
BEGIN
    DECLARE @Ortalama DECIMAL(3,2);
    SELECT @Ortalama = AVG(CAST(Puan AS DECIMAL(3,2)))
    FROM Yorumlar
    WHERE EvID = @EvID;
    RETURN ISNULL(@Ortalama, 0);
END;
CREATE FUNCTION FN_KiraciSayisi ()
RETURNS INT
AS
BEGIN
    DECLARE @Sayi INT;
    SELECT @Sayi = COUNT(*) FROM Kullanicilar WHERE Rol = 2;
    RETURN @Sayi;
END;
CREATE FUNCTION FN_EvSahibiSayisi ()
RETURNS INT
AS
BEGIN
    DECLARE @Sayi INT;
    SELECT @Sayi = COUNT(*) FROM Kullanicilar WHERE Rol = 1;
    RETURN @Sayi;
END;
CREATE PROCEDURE SP_EvEkle
    @SahipID INT,
    @Baslik NVARCHAR(50),
    @Aciklama NVARCHAR(200),
    @Fiyat DECIMAL(10,2),
    @Konum NVARCHAR(50),
    @FotoUrl NVARCHAR(MAX) = NULL
AS
BEGIN
    -- Ev ekleme işlemi
    INSERT INTO Evler (SahipID, Baslik, Aciklama, Fiyat, Konum, FotoUrl)
    VALUES (@SahipID, @Baslik, @Aciklama, @Fiyat, @Konum, @FotoUrl);
END;





EXEC SP_EvEkle 
    @SahipID = 49,
    @Baslik = 'Gökyüzü Evi',
    @Aciklama = 'Yüksek tepede, yıldızları izleyebileceğiniz bir ev.',
    @Fiyat = 1600.00,
    @Konum = 'Nevşehir',
    @FotoUrl = '["C:\\Images\\Ev8\\1.jpg", "C:\\Images\\Ev8\\2.jpg"]';

SELECT dbo.FN_KiraciSayisi() AS Sayi
EXECUTE SP_YorumlariGetir 45;
EXEC SP_YeniKullaniciEkle 
    @Ad = 'Ahmet', 
    @Soyad = 'Yılmaz', 
    @Email = 'ahmety@example.com', 
    @Sifre = '1234', 
    @Rol = 2;  -- 1: Ev Sahibi, 2: Kiracı

SELECT * 
FROM Evler
SELECT * 
FROM Kullanicilar
SELECT *
FROM Rezervasyonlar
SELECT *
FROM Odemeler
SELECT *
FROM Yorumlar


INSERT INTO Yorumlar (EvID, KullaniciID, Puan, Yorum)
VALUES 
(45, 21, 5, 'Harika bir deneyimdi!'),
(48, 26, 3, 'Soguktu ama ev guzeldi');
INSERT INTO Odemeler (RezervasyonID, Tutar, OdemeDurumu)
VALUES 
(10, 0, 0),  -- Bekliyor
(11, 0, 1),  -- Ödendi
(5, 0, 1),  -- Ödendi
(4, 0, 2),  -- İptal
(9, 0, 0);  -- Bekliyor
INSERT INTO Rezervasyonlar (KiraciID, EvID, BaslangicTarihi, BitisTarihi)
VALUES 
(22, 46, '2025-06-15', '2025-06-20'),
(25, 46, '2025-07-17', '2025-07-24'),
(26, 48, '2025-07-10', '2025-07-17');
INSERT INTO Evler (SahipID, Baslik, Aciklama, Fiyat, Konum, FotoUrl)
VALUES 
(23, 'Deniz Manzarali', 'Ege sahillerinde harika bir manzara', 1500.00, 'Çeşme', '["C:\\Images\\Ev4\\1.jpg", "C:\\Images\\Ev4\\2.jpg"]'),
(24, 'Modern Tiny House', 'Minimalist yasam sevenler icin', 1000.00, 'İzmir', '["C:\\Images\\Ev5\\1.jpg", "C:\\Images\\Ev5\\2.jpg"]'),
(27, 'Rustik Kulube', 'Romantik bir tatil icin uygun', 1300.00, 'Abant', '["C:\\Images\\Ev8\\1.jpg", "C:\\Images\\Ev8\\2.jpg"]'),
(28, 'Sehir Merkezinde', 'Her yere yürüme mesafesinde', 1400.00, 'İstanbul', '["C:\\Images\\Ev9\\1.jpg", "C:\\Images\\Ev9\\2.jpg"]'),
(23, 'Nehir Kenari', 'Balik tutmak isteyenler icin', 1050.00, 'Amasya', '["C:\\Images\\Ev10\\1.jpg", "C:\\Images\\Ev10\\2.jpg"]');

ALTER TABLE Odemeler
DROP CONSTRAINT CK__Odemeler__Tutar__778AC167;
ALTER TABLE Odemeler
ADD CONSTRAINT CK__Odemeler__Tutar
CHECK (Tutar >= 0);
ALTER TABLE Yorumlar
DROP CONSTRAINT CK__Yorumlar__Yorum;
ALTER TABLE Yorumlar
ADD CONSTRAINT CK__Yorumlar__Yorum
CHECK (
  Yorum NOT LIKE '%<%' AND
  Yorum NOT LIKE '%>%' AND
  Yorum NOT LIKE '%''%' AND
  Yorum NOT LIKE '%;%' AND
  Yorum NOT LIKE '%--%' AND
  Yorum NOT LIKE '%@%' AND
  Yorum NOT LIKE '%#%' AND
  Yorum NOT LIKE '%$%' AND
  Yorum NOT LIKE '%^%' AND
  Yorum NOT LIKE '%&%' AND
  Yorum NOT LIKE '%*%' AND
  Yorum NOT LIKE '%(%' AND
  Yorum NOT LIKE '%)%'
);



SET IDENTITY_INSERT Kullanicilar ON;
INSERT INTO Kullanicilar (KullaniciID, Ad, Soyad, Email, Sifre, Rol, Aktif)
VALUES (1, 'Batuhan', 'ARIK', 'ARK@gmail.com', 'Batu123', 0, 1);
SET IDENTITY_INSERT Kullanicilar OFF;