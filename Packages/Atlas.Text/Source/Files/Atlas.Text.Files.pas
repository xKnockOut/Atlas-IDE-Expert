unit Atlas.Text.Files;

// Kleine Dateiaktionen (gemeinsam für Server und Plugin) für Austausch-,
// Status- und Sperrdateien, die ein anderer Prozess schon gelöscht oder
// gerade offen haben kann:
// - DeleteQuietly löscht ohne Fehlermeldung.
// - OpenExclusive öffnet bzw. legt eine Datei so an, dass kein anderer sie
//   zugleich offen hat. Ohne Ausnahme: Das Ergebnis unterscheidet „ein anderer
//   hält sie“ (Locked, Warten lohnt) von „geht nie“ (Failed, z. B. kein
//   Schreibrecht, Ordner fehlt, Name ist ein Ordner; sofort aufgeben). Unter
//   Windows heißt Locked ERROR_SHARING_VIOLATION bzw. ERROR_LOCK_VIOLATION,
//   unter Linux EWOULDBLOCK von flock.
// - IsFileError trennt Fehler des Dateisystems (fehlt, gesperrt, keine Rechte,
//   ungültiger Pfad, falsche Kodierung) von allem anderen: Wer „Datei nicht
//   lesbar“ als Ergebnis zurückgibt, fängt nur diese und lässt Programmfehler
//   weiter zur Fehlergrenze.

interface

uses
  System.SysUtils,
  System.Classes;

type
{$SCOPEDENUMS ON}
  /// <summary>Ergebnis von TTextFiles.OpenExclusive.</summary>
  TTextExclusiveOpen = (
    /// <summary>Offen; der Aufrufer gibt den Stream frei.</summary>
    Opened,
    /// <summary>Datei fehlt und sollte nicht angelegt werden.</summary>
    Missing,
    /// <summary>Ein anderer hält die Datei offen; später neu versuchen.</summary>
    Locked,
    /// <summary>Geht nie (Rechte, Pfad); Warten hilft nicht.</summary>
    Failed);
{$SCOPEDENUMS OFF}

  TTextFiles = class
  public
    /// <summary>Löscht AFileName, wenn es sie gibt; Dateifehler (gesperrt, keine Rechte) bleiben still.</summary>
    class procedure DeleteQuietly(const AFileName: string); static;
    /// <summary>Löscht den Ordner AFolder mit Inhalt, wenn es ihn gibt. False bei einem Dateifehler (gesperrt,
    /// keine Rechte); andere Fehler gehen weiter.</summary>
    class function DeleteFolder(const AFolder: string): Boolean; static;
    /// <summary>Letzte Änderung der Datei oder des Ordners APath in UTC. False (AUtc 0), wenn es ihn nicht gibt
    /// oder er gerade gelöscht oder gesperrt ist.</summary>
    class function LastWriteUtc(const APath: string; out AUtc: TDateTime): Boolean; static;
    /// <summary>Öffnet AFileName zum Lesen und Schreiben, ohne dass ein anderer sie zugleich offen haben darf;
    /// fehlt sie, legt ACreate sie leer an. AStream nur bei Opened, sonst nil. AError: Text des Betriebssystems
    /// bei Failed, sonst ''.</summary>
    class function OpenExclusive(const AFileName: string; ACreate: Boolean; out AStream: TStream;
      out AError: string): TTextExclusiveOpen; overload; static;
    /// <summary>Wie oben, wartet bei Locked aber bis zu AWaitMs in Schritten von AStepMs; Failed und Missing kehren
    /// sofort zurück.</summary>
    class function OpenExclusive(const AFileName: string; ACreate: Boolean; AWaitMs, AStepMs: Integer;
      out AStream: TStream; out AError: string): TTextExclusiveOpen; overload; static;
    /// <summary>Fehler beim Zugriff aufs Dateisystem: EInOutError (auch EDirectoryNotFoundException,
    /// EFileNotFoundException), EStreamError (EFOpenError, EFCreateError, EReadError, EWriteError), EOSError,
    /// EEncodingError und genau EArgumentException (TPath bei ungültigen Zeichen, nicht dessen Nachfahren wie
    /// EArgumentOutOfRangeException).</summary>
    class function IsFileError(AE: Exception): Boolean; static;
    /// <summary>Letzter Fehler des Betriebssystems (GetLastOSError gibt es nur unter FPC, Delphi kennt dafür
    /// System.GetLastError).</summary>
    class function LastOSError: Integer; static;
  end;

implementation

uses
  System.IOUtils;

const
{$IFDEF MSWINDOWS}
  /// <summary>ERROR_SHARING_VIOLATION und ERROR_LOCK_VIOLATION (Winapi.Windows ist hier tabu).</summary>
  cLockedErrors: array[0..1] of Integer = (32, 33);
{$ELSE}
  /// <summary>EAGAIN bzw. EWOULDBLOCK von flock (Linux, gleicher Wert).</summary>
  cLockedErrors: array[0..0] of Integer = (11);
{$ENDIF}
  /// <summary>Rechte einer neuen Datei unter Linux (rw-rw-rw- vor umask, wie TFileStream); Windows übergeht sie.
  /// </summary>
  cNewFileRights = 438;
  cInvalidHandle = THandle(-1);

type
  /// <summary>Stream über einen eigenen Dateigriff; schließt ihn beim Freigeben.</summary>
  TTextExclusiveStream = class(THandleStream)
  public
    destructor Destroy; override;
  end;

{ TTextExclusiveStream }

destructor TTextExclusiveStream.Destroy;
begin
  FileClose(Handle);
  inherited;
end;

function IsLockedError(AError: Integer): Boolean;
var
  mLocked: Integer;
begin
  Result := False;
  for mLocked in cLockedErrors do
  begin
    if AError = mLocked then
    begin
      Exit(True);
    end;
  end;
end;

{ TTextFiles }

class function TTextFiles.IsFileError(AE: Exception): Boolean;
begin
  Result := (AE is EInOutError) or (AE is EStreamError) or (AE is EOSError) or (AE is EEncodingError) or
    (AE.ClassType = EArgumentException);
end;

class function TTextFiles.LastOSError: Integer;
begin
{$IFDEF FPC}
  Result := GetLastOSError;
{$ELSE}
  Result := Integer(System.GetLastError);
{$ENDIF}
end;

class function TTextFiles.OpenExclusive(const AFileName: string; ACreate: Boolean; out AStream: TStream;
  out AError: string): TTextExclusiveOpen;
var
  mHandle: THandle;
  mError: Integer;
begin
  AStream := nil;
  AError := '';
  if FileExists(AFileName) then
  begin
    mHandle := FileOpen(AFileName, fmOpenReadWrite or fmShareExclusive);
  end
  else if ACreate then
  begin
    mHandle := FileCreate(AFileName, fmShareExclusive, cNewFileRights);
  end
  else
  begin
    Exit(TTextExclusiveOpen.Missing);
  end;
  if mHandle <> cInvalidHandle then
  begin
    AStream := TTextExclusiveStream.Create(mHandle);
    Exit(TTextExclusiveOpen.Opened);
  end;
  mError := LastOSError;
  if IsLockedError(mError) then
  begin
    Exit(TTextExclusiveOpen.Locked);
  end;
  AError := SysErrorMessage(mError);
  Result := TTextExclusiveOpen.Failed;
end;

class function TTextFiles.OpenExclusive(const AFileName: string; ACreate: Boolean; AWaitMs, AStepMs: Integer;
  out AStream: TStream; out AError: string): TTextExclusiveOpen;
var
  mWaited: Integer;
begin
  mWaited := 0;
  repeat
    Result := OpenExclusive(AFileName, ACreate, AStream, AError);
    if (Result <> TTextExclusiveOpen.Locked) or (mWaited >= AWaitMs) then
    begin
      Exit;
    end;
    Sleep(AStepMs);
    Inc(mWaited, AStepMs);
  until False;
end;

class procedure TTextFiles.DeleteQuietly(const AFileName: string);
begin
  try
    if TFile.Exists(AFileName) then
    begin
      TFile.Delete(AFileName);
    end;
  except
    // Austausch- und Statusdateien nach Kräften.
    on E: Exception do
    begin
      if not IsFileError(E) then
      begin
        raise;
      end;
    end;
  end;
end;

class function TTextFiles.LastWriteUtc(const APath: string; out AUtc: TDateTime): Boolean;
begin
  Result := False;
  AUtc := 0;
  try
    if FileExists(APath) then
    begin
      AUtc := TFile.GetLastWriteTimeUtc(APath);
      Result := True;
    end
    else if DirectoryExists(APath) then
    begin
      AUtc := TDirectory.GetLastWriteTimeUtc(APath);
      Result := True;
    end;
  except
    on E: Exception do
    begin
      if not IsFileError(E) then
      begin
        raise;
      end;
      AUtc := 0;
      Result := False;
    end;
  end;
end;

class function TTextFiles.DeleteFolder(const AFolder: string): Boolean;
begin
  Result := True;
  try
    if TDirectory.Exists(AFolder) then
    begin
      TDirectory.Delete(AFolder, True);
    end;
  except
    on E: Exception do
    begin
      if not IsFileError(E) then
      begin
        raise;
      end;
      Result := False;
    end;
  end;
end;

end.
