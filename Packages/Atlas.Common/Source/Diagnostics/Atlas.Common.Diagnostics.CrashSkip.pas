unit Atlas.Common.Diagnostics.CrashSkip;

// Sicherheitsnetz nach Abstürzen (#1355), ausdrücklich zusätzlich zur
// Behebung der Ursache, nicht statt ihr: Merkt sich je (Methode, Datei,
// Prüfsumme des Inhalts) die Abstürze. Ab dem zweiten Absturz derselben
// Kombination (Threshold) beantwortet der Server diese Anfrage für diese Datei
// mit „Übersprungen nach Absturz“, bis sich der Inhalt der Datei ändert
// (andere Prüfsumme) oder der Benutzer „Erneut versuchen“ wählt (Retry).
// Den Fall zum Absturz (TCrashCases) nennt der Eintrag, damit Log, Statusleiste
// und Prüffenster auf ihn verweisen.
// Watched prüft ohne Prüfsumme, ob für Methode und Datei überhaupt etwas
// gemerkt ist; erst dann rechnet der Aufrufer die Prüfsumme (FNV-1a, 64 Bit)
// über den Text. Nur Anfragen mit Dokument (textDocument.uri) zählen: Ohne
// Datei gäbe es keine Änderung, die das Überspringen beendet.
// ToJson/Load halten den Merker über einen Neustart des Servers hinweg.
// Threadsicher: Abstürze melden Worker-Threads, die Prüfung läuft im Thread
// der Nachrichtenschleife.

interface

uses
  System.SysUtils,
  System.Generics.Collections;

type
  TCrashSkipEntry = record
    Method: string;
    Uri: string;
    Checksum: string;
    Crashes: Integer;
    /// <summary>Ordner des letzten Falls; '' ohne.</summary>
    CaseFolder: string;
    ExceptionClass: string;
    /// <summary>Wird übersprungen (Crashes &gt;= Threshold)?</summary>
    function Skipping: Boolean;
  end;

  TCrashSkips = class
  public const
    /// <summary>Ab so vielen Abstürzen derselben Kombination wird übersprungen.</summary>
    Threshold = 2;
    /// <summary>Höchstens so viele Einträge; ältere fallen weg.</summary>
    MaxEntries = 200;
  private
    FLock: TObject;
    FEntries: TList<TCrashSkipEntry>;
    function IndexOf(const AMethod, AUri: string): Integer;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Ein Absturz von AMethod an AUri mit Inhalt AChecksum. True, wenn die Kombination ab jetzt
    /// übersprungen wird (zweiter Absturz). Ein anderer Inhalt zählt von vorn.</summary>
    function Crashed(const AMethod, AUri, AChecksum, ACaseFolder, AExceptionClass: string): Boolean;
    /// <summary>Ist für AMethod und AUri etwas gemerkt (ohne Prüfsumme)?</summary>
    function Watched(const AMethod, AUri: string): Boolean;
    /// <summary>Ist für AUri irgendeine Methode gemerkt?</summary>
    function WatchedUri(const AUri: string): Boolean;
    /// <summary>Soll AMethod für AUri mit Inhalt AChecksum übersprungen werden? Hat sich der Inhalt geändert,
    /// fällt der Eintrag weg (AChanged) und es wird nicht übersprungen.</summary>
    function Skip(const AMethod, AUri, AChecksum: string; out AEntry: TCrashSkipEntry;
      out AChanged: Boolean): Boolean;
    /// <summary>Inhalt von AUri ist jetzt AChecksum: Einträge mit anderem Inhalt fallen weg; liefert die, die
    /// übersprungen wurden.</summary>
    function Changed(const AUri, AChecksum: string): TArray<TCrashSkipEntry>;
    /// <summary>„Erneut versuchen“: alle Einträge von AUri ('' = alle); liefert die, die übersprungen wurden.
    /// </summary>
    function Retry(const AUri: string): TArray<TCrashSkipEntry>;
    /// <summary>Alle Einträge, die gerade übersprungen werden.</summary>
    function Skipped: TArray<TCrashSkipEntry>;
    function Count: Integer;
    /// <summary>Alle Einträge als JSON-Array.</summary>
    function ToJson: string;
    /// <summary>Ersetzt die Einträge durch die aus AJson; unlesbares JSON ergibt keine.</summary>
    procedure Load(const AJson: string);
    /// <summary>FNV-1a mit 64 Bit über die UTF-16-Zeichen, 16 Hex-Zeichen.</summary>
    class function Checksum(const AText: string): string; static;
  end;

implementation

uses
  System.JSON,
  Atlas.Common.Diagnostics.CrashCase;

{ TCrashSkipEntry }

function TCrashSkipEntry.Skipping: Boolean;
begin
  Result := Crashes >= TCrashSkips.Threshold;
end;

{ TCrashSkips }

constructor TCrashSkips.Create;
begin
  inherited Create;
  FLock := TObject.Create;
  FEntries := TList<TCrashSkipEntry>.Create;
end;

destructor TCrashSkips.Destroy;
begin
  FEntries.Free;
  FLock.Free;
  inherited;
end;

// FNV-1a rechnet modulo 2^64: die Überlaufprüfung ist nur hier aus, danach wie vorher (#972).
{$IFOPT Q+}{$DEFINE ATLAS_HASH_UEBERLAUF}{$Q-}{$ENDIF}
class function TCrashSkips.Checksum(const AText: string): string;
var
  mHash: UInt64;
  mIndex: Integer;
begin
  mHash := UInt64($CBF29CE484222325);
  for mIndex := 1 to Length(AText) do
  begin
    mHash := mHash xor Ord(AText[mIndex]);
    mHash := mHash * UInt64($00000100000001B3);
  end;
  Result := IntToHex(Int64(mHash), 16);
end;
{$IFDEF ATLAS_HASH_UEBERLAUF}{$Q+}{$UNDEF ATLAS_HASH_UEBERLAUF}{$ENDIF}

function TCrashSkips.IndexOf(const AMethod, AUri: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to FEntries.Count - 1 do
    if (FEntries[mIndex].Method = AMethod) and SameText(FEntries[mIndex].Uri, AUri) then
      Exit(mIndex);
  Result := -1;
end;

function TCrashSkips.Crashed(const AMethod, AUri, AChecksum, ACaseFolder, AExceptionClass: string): Boolean;
var
  mIndex: Integer;
  mEntry: TCrashSkipEntry;
begin
  Result := False;
  if (AMethod = '') or (AUri = '') then
    Exit;
  System.TMonitor.Enter(FLock);
  try
    mIndex := IndexOf(AMethod, AUri);
    if mIndex >= 0 then
    begin
      mEntry := FEntries[mIndex];
      FEntries.Delete(mIndex);
      if mEntry.Checksum <> AChecksum then
        mEntry.Crashes := 0;
    end
    else
    begin
      mEntry := Default(TCrashSkipEntry);
      mEntry.Method := AMethod;
      mEntry.Uri := AUri;
    end;
    mEntry.Checksum := AChecksum;
    Inc(mEntry.Crashes);
    if ACaseFolder <> '' then
      mEntry.CaseFolder := ACaseFolder;
    mEntry.ExceptionClass := AExceptionClass;
    // Zuletzt abgestürzt steht hinten; vorne fällt bei Überlauf das Älteste weg.
    FEntries.Add(mEntry);
    while FEntries.Count > MaxEntries do
      FEntries.Delete(0);
    Result := mEntry.Crashes = Threshold;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function TCrashSkips.Watched(const AMethod, AUri: string): Boolean;
begin
  System.TMonitor.Enter(FLock);
  try
    Result := (FEntries.Count > 0) and (IndexOf(AMethod, AUri) >= 0);
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function TCrashSkips.WatchedUri(const AUri: string): Boolean;
var
  mEntry: TCrashSkipEntry;
begin
  Result := False;
  System.TMonitor.Enter(FLock);
  try
    for mEntry in FEntries do
      if SameText(mEntry.Uri, AUri) then
        Exit(True);
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function TCrashSkips.Skip(const AMethod, AUri, AChecksum: string; out AEntry: TCrashSkipEntry;
  out AChanged: Boolean): Boolean;
var
  mIndex: Integer;
begin
  AEntry := Default(TCrashSkipEntry);
  AChanged := False;
  Result := False;
  System.TMonitor.Enter(FLock);
  try
    mIndex := IndexOf(AMethod, AUri);
    if mIndex < 0 then
      Exit;
    AEntry := FEntries[mIndex];
    if AEntry.Checksum <> AChecksum then
    begin
      FEntries.Delete(mIndex);
      AChanged := AEntry.Skipping;
      Exit;
    end;
    Result := AEntry.Skipping;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function TCrashSkips.Changed(const AUri, AChecksum: string): TArray<TCrashSkipEntry>;
var
  mIndex: Integer;
begin
  Result := nil;
  System.TMonitor.Enter(FLock);
  try
    for mIndex := FEntries.Count - 1 downto 0 do
      if SameText(FEntries[mIndex].Uri, AUri) and (FEntries[mIndex].Checksum <> AChecksum) then
      begin
        if FEntries[mIndex].Skipping then
          Result := Result + [FEntries[mIndex]];
        FEntries.Delete(mIndex);
      end;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function TCrashSkips.Retry(const AUri: string): TArray<TCrashSkipEntry>;
var
  mIndex: Integer;
begin
  Result := nil;
  System.TMonitor.Enter(FLock);
  try
    for mIndex := FEntries.Count - 1 downto 0 do
      if (AUri = '') or SameText(FEntries[mIndex].Uri, AUri) then
      begin
        if FEntries[mIndex].Skipping then
          Result := Result + [FEntries[mIndex]];
        FEntries.Delete(mIndex);
      end;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function TCrashSkips.Skipped: TArray<TCrashSkipEntry>;
var
  mEntry: TCrashSkipEntry;
begin
  Result := nil;
  System.TMonitor.Enter(FLock);
  try
    for mEntry in FEntries do
      if mEntry.Skipping then
        Result := Result + [mEntry];
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function TCrashSkips.Count: Integer;
begin
  System.TMonitor.Enter(FLock);
  try
    Result := FEntries.Count;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function TCrashSkips.ToJson: string;
var
  mArray: TJSONArray;
  mItem: TJSONObject;
  mEntry: TCrashSkipEntry;
begin
  mArray := TJSONArray.Create;
  try
    System.TMonitor.Enter(FLock);
    try
      for mEntry in FEntries do
      begin
        mItem := TJSONObject.Create;
        mArray.AddElement(mItem);
        mItem.AddPair('method', mEntry.Method);
        mItem.AddPair('uri', mEntry.Uri);
        mItem.AddPair('checksum', mEntry.Checksum);
        mItem.AddPair('crashes', TJSONNumber.Create(mEntry.Crashes));
        mItem.AddPair('case', mEntry.CaseFolder);
        mItem.AddPair('exception', mEntry.ExceptionClass);
      end;
    finally
      System.TMonitor.Exit(FLock);
    end;
    Result := mArray.ToJSON;
  finally
    mArray.Free;
  end;
end;

function StringOf(const AObject: TJSONObject; const AName: string): string;
var
  mValue: TJSONValue;
begin
  Result := '';
  mValue := AObject.GetValue(AName);
  if mValue is TJSONString then
    Result := mValue.Value;
end;

procedure TCrashSkips.Load(const AJson: string);
var
  mRoot, mValue: TJSONValue;
  mIndex: Integer;
  mItem: TJSONObject;
  mEntry: TCrashSkipEntry;
begin
  mRoot := TCrashCases.ParseOrNil(AJson);
  try
    System.TMonitor.Enter(FLock);
    try
      FEntries.Clear;
      if not (mRoot is TJSONArray) then
        Exit;
      for mIndex := 0 to TJSONArray(mRoot).Count - 1 do
      begin
        if not (TJSONArray(mRoot).Items[mIndex] is TJSONObject) then
          Continue;
        mItem := TJSONObject(TJSONArray(mRoot).Items[mIndex]);
        mEntry := Default(TCrashSkipEntry);
        mEntry.Method := StringOf(mItem, 'method');
        mEntry.Uri := StringOf(mItem, 'uri');
        mEntry.Checksum := StringOf(mItem, 'checksum');
        mEntry.CaseFolder := StringOf(mItem, 'case');
        mEntry.ExceptionClass := StringOf(mItem, 'exception');
        mValue := mItem.GetValue('crashes');
        if mValue is TJSONNumber then
          mEntry.Crashes := TJSONNumber(mValue).AsInt;
        if (mEntry.Method <> '') and (mEntry.Uri <> '') and (mEntry.Crashes > 0) then
          FEntries.Add(mEntry);
      end;
      while FEntries.Count > MaxEntries do
        FEntries.Delete(0);
    finally
      System.TMonitor.Exit(FLock);
    end;
  finally
    mRoot.Free;
  end;
end;

end.
