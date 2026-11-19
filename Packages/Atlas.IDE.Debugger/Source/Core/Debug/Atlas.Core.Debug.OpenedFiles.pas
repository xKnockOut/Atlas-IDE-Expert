unit Atlas.Core.Debug.OpenedFiles;

// Buchführung „vom Debugger geöffnete Dateien“ (#842), ohne VCL und Open Tools
// API:
//   - BeginSession merkt die Dateien, die vor der Sitzung offen waren; sie
//     werden nie geschlossen.
//   - Eine Datei, die während der Sitzung aufgeht, zählt als vom Debugger
//     geöffnet, wenn sie die Stelle des Halts ist (F7 in eine Unit der RTL)
//     oder ein Halt in ihr kurz darauf folgt (cStopWindowMs: Die IDE öffnet
//     die Datei manchmal, bevor sie den Halt meldet). Was der Benutzer im
//     Halt selbst öffnet (andere Datei), zählt nicht.
//   - Fest (Pin) wird eine Datei, an der der Benutzer etwas getan hat (Tippen,
//     Haltepunkt, Lesezeichen, Anheften); sie bleibt offen.
//   - ToClose nennt nach der Sitzung, was noch offen und nicht fest ist; die
//     IDE-Schicht prüft dabei über AKeep, was sich nur dort sehen lässt.
//   - Vorschau (debug.previewTab): PreviewToClose nennt die vorige vom
//     Debugger geöffnete Datei, sobald er eine neue öffnet.
// Dateinamen ohne Unterschied von Groß-/Kleinschreibung und „/“ bzw. „\“.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Settings.Plugin.Debug;

type
  {$SCOPEDENUMS ON}
  /// <summary>debug.closeOpenedFiles: nichts tun, nach der Sitzung fragen, selbst schließen.</summary>
  TAtlasCloseOpenedFiles = (Off, Ask, Auto);
  {$SCOPEDENUMS OFF}

  /// <summary>True: Datei bleibt offen (geändert, Haltepunkt, Lesezeichen).</summary>
  TAtlasOpenedFileKeep = reference to function(const AFileName: string): Boolean;

  TAtlasOpenedFiles = class
  public const
    cStopWindowMs = 2000;
  private
    FActive: Boolean;
    FBefore: TDictionary<string, Boolean>;
    FPinned: TDictionary<string, Boolean>;
    FPending: TDictionary<string, UInt64>;
    FOpened: TList<string>;
    FPreview: string;
    function IndexOfOpened(const AFileName: string): Integer;
    procedure AddOpened(const AFileName: string);
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Neue Sitzung; AOpenFiles waren schon offen.</summary>
    procedure BeginSession(const AOpenFiles: TArray<string>);
    /// <summary>Sitzung zu Ende: weitere Meldungen zählen nicht mehr, die Liste bleibt bis zur nächsten.</summary>
    procedure EndSession;
    /// <summary>AFileName ist zur Zeit ATick (ms) aufgegangen, AAtStop: Programm angehalten und AFileName ist die
    /// Stelle des Halts. True, wenn sie damit als vom Debugger geöffnet zählt.</summary>
    function Opened(const AFileName: string; AAtStop: Boolean; ATick: UInt64): Boolean;
    /// <summary>Halt in AFileName zur Zeit ATick: Ging sie höchstens cStopWindowMs vorher auf, zählt sie als vom
    /// Debugger geöffnet (True).</summary>
    function Stopped(const AFileName: string; ATick: UInt64): Boolean;
    /// <summary>AFileName wurde geschlossen.</summary>
    procedure Closed(const AFileName: string);
    /// <summary>AFileName bleibt offen, egal was kommt.</summary>
    procedure Pin(const AFileName: string);
    function IsPinned(const AFileName: string): Boolean;
    /// <summary>Vom Debugger geöffnet und noch offen?</summary>
    function IsOpenedByDebugger(const AFileName: string): Boolean;
    /// <summary>Vorschau: ANew hat der Debugger gerade geöffnet; Ergebnis ist die vorige so geöffnete Datei, die
    /// nicht fest ist und nicht AKeep erfüllt ('' ohne). ANew wird die neue Vorschau.</summary>
    function PreviewToClose(const ANew: string; const AKeep: TAtlasOpenedFileKeep): string;
    /// <summary>Was nach der Sitzung zu schließen ist: vom Debugger geöffnet, noch offen, nicht fest und nicht AKeep,
    /// in der Reihenfolge des Öffnens.</summary>
    function ToClose(const AKeep: TAtlasOpenedFileKeep): TArray<string>;
    /// <summary>Vom Debugger geöffnete, noch offene Dateien.</summary>
    function Count: Integer;
    /// <summary>Wert von debug.closeOpenedFiles; Unbekanntes gilt als Ask (Vorgabe).</summary>
    class function ModeOf(const AText: string): TAtlasCloseOpenedFiles; static;
    /// <summary>Wert von AMode in debug.closeOpenedFiles (cCloseOpenedFilesModes).</summary>
    class function NameOf(AMode: TAtlasCloseOpenedFiles): string; static;
    /// <summary>Schlüssel einer Datei: groß, „/“ als „\“.</summary>
    class function KeyOf(const AFileName: string): string; static;
    property Active: Boolean read FActive;
    property Preview: string read FPreview;
  end;

implementation

{ TAtlasOpenedFiles }

constructor TAtlasOpenedFiles.Create;
begin
  inherited Create;
  FBefore := TDictionary<string, Boolean>.Create;
  FPinned := TDictionary<string, Boolean>.Create;
  FPending := TDictionary<string, UInt64>.Create;
  FOpened := TList<string>.Create;
end;

destructor TAtlasOpenedFiles.Destroy;
begin
  FreeAndNil(FOpened);
  FreeAndNil(FPending);
  FreeAndNil(FPinned);
  FreeAndNil(FBefore);
  FPreview := '';
  inherited Destroy;
end;

class function TAtlasOpenedFiles.KeyOf(const AFileName: string): string;
begin
  Result := UpperCase(StringReplace(Trim(AFileName), '/', '\', [rfReplaceAll]));
end;

class function TAtlasOpenedFiles.ModeOf(const AText: string): TAtlasCloseOpenedFiles;
var
  mMode: TAtlasCloseOpenedFiles;
begin
  for mMode := Low(TAtlasCloseOpenedFiles) to High(TAtlasCloseOpenedFiles) do
  begin
    if SameText(Trim(AText), NameOf(mMode)) then
    begin
      Exit(mMode);
    end;
  end;
  Result := TAtlasCloseOpenedFiles.Ask;
end;

class function TAtlasOpenedFiles.NameOf(AMode: TAtlasCloseOpenedFiles): string;
begin
  Result := cCloseOpenedFilesModes[Ord(AMode)];
end;

procedure TAtlasOpenedFiles.BeginSession(const AOpenFiles: TArray<string>);
var
  mFile: string;
begin
  FBefore.Clear;
  FPinned.Clear;
  FPending.Clear;
  FOpened.Clear;
  FPreview := '';
  for mFile in AOpenFiles do
  begin
    FBefore.AddOrSetValue(KeyOf(mFile), True);
  end;
  FActive := True;
end;

procedure TAtlasOpenedFiles.EndSession;
begin
  FActive := False;
  FPending.Clear;
  FPreview := '';
end;

function TAtlasOpenedFiles.IndexOfOpened(const AFileName: string): Integer;
var
  mKey: string;
begin
  mKey := KeyOf(AFileName);
  for Result := 0 to FOpened.Count - 1 do
  begin
    if KeyOf(FOpened[Result]) = mKey then
    begin
      Exit;
    end;
  end;
  Result := -1;
end;

procedure TAtlasOpenedFiles.AddOpened(const AFileName: string);
begin
  if IndexOfOpened(AFileName) < 0 then
  begin
    FOpened.Add(AFileName);
  end;
end;

function TAtlasOpenedFiles.Opened(const AFileName: string; AAtStop: Boolean; ATick: UInt64): Boolean;
var
  mKey: string;
begin
  Result := False;
  mKey := KeyOf(AFileName);
  if not FActive or (mKey = '') or FBefore.ContainsKey(mKey) then
  begin
    Exit;
  end;
  if not AAtStop then
  begin
    // Erst mit einem Halt in der Datei steht fest, dass der Debugger sie geöffnet hat.
    FPending.AddOrSetValue(mKey, ATick);
    Exit;
  end;
  AddOpened(AFileName);
  Result := True;
end;

function TAtlasOpenedFiles.Stopped(const AFileName: string; ATick: UInt64): Boolean;
var
  mKey: string;
  mOpenedAt: UInt64;
begin
  Result := False;
  mKey := KeyOf(AFileName);
  if not FActive or not FPending.TryGetValue(mKey, mOpenedAt) then
  begin
    Exit;
  end;
  FPending.Remove(mKey);
  if (ATick >= mOpenedAt) and (ATick - mOpenedAt <= cStopWindowMs) then
  begin
    AddOpened(AFileName);
    Result := True;
  end;
end;

procedure TAtlasOpenedFiles.Closed(const AFileName: string);
var
  mIndex: Integer;
  mKey: string;
begin
  mKey := KeyOf(AFileName);
  mIndex := IndexOfOpened(AFileName);
  if mIndex >= 0 then
  begin
    FOpened.Delete(mIndex);
  end;
  FPending.Remove(mKey);
  FPinned.Remove(mKey);
  // Später wieder geöffnet, gilt sie nicht mehr als „schon vor der Sitzung offen“.
  FBefore.Remove(mKey);
  if KeyOf(FPreview) = mKey then
  begin
    FPreview := '';
  end;
end;

procedure TAtlasOpenedFiles.Pin(const AFileName: string);
begin
  FPinned.AddOrSetValue(KeyOf(AFileName), True);
end;

function TAtlasOpenedFiles.IsPinned(const AFileName: string): Boolean;
begin
  Result := FPinned.ContainsKey(KeyOf(AFileName));
end;

function TAtlasOpenedFiles.IsOpenedByDebugger(const AFileName: string): Boolean;
begin
  Result := IndexOfOpened(AFileName) >= 0;
end;

/// <summary>Bleibt AFileName offen: fest oder nach AKeep?</summary>
function Kept(AFiles: TAtlasOpenedFiles; const AFileName: string; const AKeep: TAtlasOpenedFileKeep): Boolean;
begin
  Result := AFiles.IsPinned(AFileName) or (Assigned(AKeep) and AKeep(AFileName));
end;

function TAtlasOpenedFiles.PreviewToClose(const ANew: string; const AKeep: TAtlasOpenedFileKeep): string;
begin
  Result := '';
  if (FPreview <> '') and (KeyOf(FPreview) <> KeyOf(ANew)) and IsOpenedByDebugger(FPreview) and
    not Kept(Self, FPreview, AKeep) then
  begin
    Result := FPreview;
  end;
  FPreview := ANew;
end;

function TAtlasOpenedFiles.ToClose(const AKeep: TAtlasOpenedFileKeep): TArray<string>;
var
  mFile: string;
begin
  Result := nil;
  for mFile in FOpened do
  begin
    if not Kept(Self, mFile, AKeep) then
    begin
      Result := Result + [mFile];
    end;
  end;
end;

function TAtlasOpenedFiles.Count: Integer;
begin
  Result := FOpened.Count;
end;

end.
