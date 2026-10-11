unit Atlas.Common.Index.Adapters.DiskFileSystem;

// IIndexFileSystem auf der echten Platte. Lesen erkennt die Kodierung wie
// beim Öffnen im Editor; Schreiben (Cache) geht über eine temporäre Datei,
// die die alte in einem Schritt ersetzt (TFile.Replace). So sieht ein Leser
// nie einen halben Cache, auch nicht nach einem Abbruch (#184).

interface

uses
  System.SysUtils,
  Atlas.Common.Index.Contract;

type
  TDiskIndexFileSystem = class(TInterfacedObject, IIndexFileSystem)
  public
    function FileStamp(const AFileName: string; out AStamp: Int64): Boolean;
    function ReadText(const AFileName: string; out AText: string): Boolean;
    function WriteText(const AFileName, AText: string): Boolean;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  Atlas.Common.Documents.FileEncoding;

{ TDiskIndexFileSystem }

function TDiskIndexFileSystem.FileStamp(const AFileName: string; out AStamp: Int64): Boolean;
var
  Age: TDateTime;
begin
  Result := FileAge(AFileName, Age);
  if Result then
    AStamp := Round(Age * MSecsPerDay)
  else
    AStamp := 0;
end;

function TDiskIndexFileSystem.ReadText(const AFileName: string; out AText: string): Boolean;
var
  Format: TFileFormat;
begin
  try
    AText := TFileEncoding.LoadFromFile(AFileName, Format);
    Result := True;
  except
    on EInOutError do
      Result := False;
    on EFOpenError do
      Result := False;
  end;
  if not Result then
    AText := '';
end;

function TDiskIndexFileSystem.WriteText(const AFileName, AText: string): Boolean;
var
  Temp, Backup: string;
  Written: Boolean;
begin
  // Eindeutige Namen: zwei Schreiber kommen sich nicht in die Quere.
  Temp := Format('%s.%d.tmp', [AFileName, TThread.CurrentThread.ThreadID]);
  // TFile.Replace braucht eine Sicherungsdatei: Mit '' scheitert es an
  // TPath.GetFullPath('') ("Pfad ist leer"), sobald die Zieldatei existiert.
  Backup := Format('%s.%d.bak', [AFileName, TThread.CurrentThread.ThreadID]);
  Written := False;
  try
    ForceDirectories(ExtractFileDir(AFileName));
    TFile.WriteAllText(Temp, AText, TEncoding.UTF8);
    Written := True;
    if FileExists(AFileName) then
      TFile.Replace(Temp, AFileName, Backup)
    else
      RenameFile(Temp, AFileName);
  except
    // TFile.Replace prüft vorab, ob Quelle und Ziel existieren; im Wettlauf mit einem zweiten
    // Schreiber (#62) fehlt das Ziel kurz (EFileNotFoundException).
    on EInOutError do
      ;
    on EFCreateError do
      ;
    on EArgumentException do
      ;
    on EOSError do
      ;
  end;
  // TFile.Replace wertet das Ergebnis von ReplaceFile nicht aus und wirft bei einem Fehler
  // nichts (gesperrtes Ziel, zweiter Schreiber). Gelungen ist das Schreiben genau dann, wenn
  // die temporäre Datei an die Stelle des Ziels getreten ist.
  Result := Written and not FileExists(Temp);
  // ReplaceFile kann das alte Ziel schon zur Sicherung umbenannt haben, ohne die neue Datei
  // nachzuschieben (ERROR_UNABLE_TO_MOVE_REPLACEMENT_2). Die temporäre Datei ist vollständig
  // geschrieben, also an ihre Stelle setzen; hat ein zweiter Schreiber das Ziel inzwischen
  // angelegt, scheitert das Umbenennen, und der Cache bleibt der des anderen.
  if Written and not Result and not FileExists(AFileName) then
    Result := RenameFile(Temp, AFileName);
  // Keine Reste, weder bei Erfolg noch bei Fehler (Test ConcurrentWritersLeaveReadableCache).
  if FileExists(Temp) then
    System.SysUtils.DeleteFile(Temp);
  if FileExists(Backup) then
    System.SysUtils.DeleteFile(Backup);
end;

end.
