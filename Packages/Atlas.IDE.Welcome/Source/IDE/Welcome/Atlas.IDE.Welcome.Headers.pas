unit Atlas.IDE.Welcome.Headers;

// Kopf der Atlas-Willkommensseite (#753) in der IDE: Grußzeile nach Uhrzeit
// und Vorname des Windows-Kontos, Version, Kurzstatus aus Server und Index,
// Suchfeld (#760) und Kontextmenü „Neu in Atlas“ (#756) an allen gezeigten
// Köpfen (eigener Bereich und Tafel auf der Willkommensseite der IDE, Tafel im
// Fenster „Atlas-Start“).
// Den Anzeigenamen des Kontos schlägt TAtlasWelcomeAccountName einmal im
// Hintergrund nach (bei Domänenkonten fragt Windows dafür den
// Domänencontroller; im Hauptthread kostete das bei jedem Neuzeichnen).
// Teil der Steuerung TAtlasIdeWelcome (Atlas.IDE.Welcome.Commands); nur im
// Hauptthread.

interface

uses
  System.SysUtils,
  Atlas.Core.Status.Lines,
  Atlas.Core.Welcome.AccountName,
  Atlas.UI.Welcome.Frame,
  Atlas.UI.Welcome.Header,
  Atlas.IDE.Status.Lines,
  Atlas.IDE.Welcome.Search,
  Atlas.IDE.Welcome.Areas;

type
  /// <summary>Was die Komposition für den Kurzstatus hereinreicht.</summary>
  TAtlasIdeWelcomeStatusHooks = record
    /// <summary>Phase und Version des Servers.</summary>
    ServerInfo: TFunc<TAtlasServerInfo>;
    /// <summary>Läuft die Indizierung (mit Prozent)?</summary>
    Indexing: TAtlasIndexingFunc;
    /// <summary>Units im Index (-1 unbekannt).</summary>
    Units: TFunc<Integer>;
  end;

  /// <summary>Aktuelles Suchfeld der Steuerung; nil = ohne.</summary>
  TAtlasIdeWelcomeSearchOf = reference to function: TAtlasIdeWelcomeSearch;

  TAtlasIdeWelcomeHeaders = class
  private
    FStatus: TAtlasIdeWelcomeStatusHooks;
    FAccount: TAtlasWelcomeAccountName;
    FAreas: TAtlasIdeWelcomeAreas;
    FSearchOf: TAtlasIdeWelcomeSearchOf;
  public
    /// <summary>AAreas: Quelle von „Neu in Atlas“ (gehört der Steuerung und lebt länger); AOnAccount: der Name
    /// des Kontos ist da (Kopf neu zeichnen).</summary>
    constructor Create(const AStatus: TAtlasIdeWelcomeStatusHooks; AAreas: TAtlasIdeWelcomeAreas;
      const ASearchOf: TAtlasIdeWelcomeSearchOf; const AOnAccount: TProc);
    destructor Destroy; override;
    /// <summary>Laufende Abfrage des Namens abwarten; ihr Abschluss erreicht danach nichts mehr.</summary>
    procedure Stop;
    /// <summary>Gruß und Kurzstatus, wie der Kopf sie jetzt zeigen soll.</summary>
    function Info: TAtlasWelcomeHeaderInfo;
    /// <summary>Kopf ganz füllen (Einstellungen, Suchfeld, Menü, Thema).</summary>
    procedure Fill(AHeader: TAtlasWelcomeHeaderFrame);
    /// <summary>Kontextmenü „Neu in Atlas“ an Frame „Atlas“ bzw. Kopf hängen oder (off) entfernen.</summary>
    procedure AttachMenu(AFrame: TAtlasWelcomeFrame);
    /// <summary>Alle gezeigten Köpfe ganz neu füllen.</summary>
    procedure UpdateAll;
    /// <summary>Nur Gruß und Kurzstatus aller gezeigten Köpfe; unverändert bleibt der Kopf unberührt.</summary>
    procedure UpdateInfos;
  end;

implementation

uses
  Winapi.Windows,
  Atlas.Core.Product.Version,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Welcome.Greeting,
  Atlas.Core.Welcome.Sections,
  Atlas.UI.Welcome.Board,
  Atlas.UI.Welcome.WhatsNew,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Welcome.Page,
  Atlas.IDE.Welcome.Window;

const
  cNameDisplay = 3;

function GetUserNameExW(ANameFormat: Integer; ABuffer: PWideChar; var ASize: ULONG): BOOL; stdcall;
  external 'secur32.dll' name 'GetUserNameExW';

/// <summary>Anzeigename des Windows-Kontos; fragt bei Domänenkonten den Domänencontroller (nur im Hintergrund
/// aufrufen, siehe TAtlasWelcomeAccountName).</summary>
function DisplayName: string;
var
  mSize: ULONG;
  mBuffer: array[0..255] of WideChar;
begin
  // Puffer leeren und nur die gemeldete Länge übernehmen: Bei lokalen Konten meldet die Funktion teils
  // Erfolg, ohne etwas zu schreiben; dann stand Speicherrest als Vorname im Gruß.
  FillChar(mBuffer, SizeOf(mBuffer), 0);
  mSize := Length(mBuffer);
  Result := '';
  if GetUserNameExW(cNameDisplay, @mBuffer[0], mSize) and (mSize > 0) and (mSize < ULONG(Length(mBuffer))) then
  begin
    SetString(Result, PWideChar(@mBuffer[0]), mSize);
  end;
  Result := Trim(Result);
end;

function Settings: TAtlasPluginSettings;
begin
  Result := TAtlasIdeSettings.Current;
end;

/// <summary>Nachschlagen des Anzeigenamens für TAtlasWelcomeAccountName (läuft im Hintergrund).</summary>
function AccountLookup: TFunc<string>;
begin
  Result :=
    function: string
    begin
      Result := DisplayName;
    end;
end;

/// <summary>Tafel auf der Willkommensseite der IDE; nil ohne.</summary>
function IdeBoard: TAtlasWelcomeBoardFrame;
var
  mClient: TAtlasWelcomeFrame;
begin
  Result := nil;
  mClient := TAtlasIdeWelcomePage.Client(TAtlasWelcomeIds.PluginId(TAtlasWelcomeIds.cBoard));
  if mClient is TAtlasWelcomeBoardFrame then
  begin
    Result := TAtlasWelcomeBoardFrame(mClient);
  end;
end;

/// <summary>Eigener Bereich „Kopf“ auf der Willkommensseite der IDE; nil ohne.</summary>
function IdeHeader: TAtlasWelcomeHeaderFrame;
var
  mClient: TAtlasWelcomeFrame;
begin
  Result := nil;
  mClient := TAtlasIdeWelcomePage.Client(TAtlasWelcomeIds.PluginId(TAtlasWelcomeIds.cHeader));
  if mClient is TAtlasWelcomeHeaderFrame then
  begin
    Result := TAtlasWelcomeHeaderFrame(mClient);
  end;
end;

/// <summary>Gezeigte Köpfe: eigener Bereich und Tafel auf der Willkommensseite der IDE, Tafel im Fenster
/// „Atlas-Start“.</summary>
function Shown: TArray<TAtlasWelcomeHeaderFrame>;
var
  mHeader: TAtlasWelcomeHeaderFrame;
  mBoard: TAtlasWelcomeBoardFrame;
begin
  Result := nil;
  mHeader := IdeHeader;
  if mHeader <> nil then
  begin
    Result := Result + [mHeader];
  end;
  mBoard := IdeBoard;
  if mBoard <> nil then
  begin
    Result := Result + [mBoard.Header];
  end;
  mBoard := TAtlasIdeWelcomeWindow.ExistingBoard;
  if mBoard <> nil then
  begin
    Result := Result + [mBoard.Header];
  end;
end;

/// <summary>Kopfzeile ohne Gruß: Version des Plugins (die des Servers steht im Statusfeld), Phase, Index.
/// </summary>
function StatusInfo(const AServer: TAtlasServerInfo; AIndexing: Boolean; APercent, AUnits: Integer):
  TAtlasWelcomeHeaderInfo;
begin
  Result := Default(TAtlasWelcomeHeaderInfo);
  Result.Version := TAtlasPluginVersion.cVersion;
  Result.Phase := AServer.Phase;
  Result.Units := AUnits;
  Result.Indexing := AIndexing;
  Result.Percent := APercent;
end;

{ TAtlasIdeWelcomeHeaders }

constructor TAtlasIdeWelcomeHeaders.Create(const AStatus: TAtlasIdeWelcomeStatusHooks;
  AAreas: TAtlasIdeWelcomeAreas; const ASearchOf: TAtlasIdeWelcomeSearchOf; const AOnAccount: TProc);
begin
  inherited Create;
  FStatus := AStatus;
  FAreas := AAreas;
  FSearchOf := ASearchOf;
  FAccount := TAtlasWelcomeAccountName.Create(AccountLookup(), AOnAccount);
end;

destructor TAtlasIdeWelcomeHeaders.Destroy;
begin
  Stop;
  inherited;
end;

procedure TAtlasIdeWelcomeHeaders.Stop;
begin
  FreeAndNil(FAccount);
end;

function TAtlasIdeWelcomeHeaders.Info: TAtlasWelcomeHeaderInfo;
var
  mServer: TAtlasServerInfo;
  mPercent, mUnits: Integer;
  mIndexing: Boolean;
  mHour, mMinute, mSecond, mMSec: Word;
  mName: string;
begin
  mServer := Default(TAtlasServerInfo);
  if Assigned(FStatus.ServerInfo) then
  begin
    mServer := FStatus.ServerInfo();
  end;
  mPercent := -1;
  mIndexing := False;
  if Assigned(FStatus.Indexing) then
  begin
    mIndexing := FStatus.Indexing(mPercent);
  end;
  mUnits := -1;
  if Assigned(FStatus.Units) then
  begin
    mUnits := FStatus.Units();
  end;
  DecodeTime(Now, mHour, mMinute, mSecond, mMSec);
  Result := StatusInfo(mServer, mIndexing, mPercent, mUnits);
  Result.Greeting := Settings.WelcomePageGreeting;
  Result.Hour := mHour;
  // Ohne Grußzeile kein Nachschlagen des Namens (bei Domänenkonten eine Anfrage an den Domänencontroller).
  if Result.Greeting then
  begin
    mName := '';
    if FAccount <> nil then
    begin
      mName := FAccount.Name;
    end;
    Result.FirstName := TAtlasWelcomeGreeting.FirstName(mName, GetEnvironmentVariable('USERNAME'));
  end;
end;

procedure TAtlasIdeWelcomeHeaders.Fill(AHeader: TAtlasWelcomeHeaderFrame);
var
  mSearch: TAtlasIdeWelcomeSearch;
begin
  if AHeader = nil then
  begin
    Exit;
  end;
  mSearch := nil;
  if Assigned(FSearchOf) then
  begin
    mSearch := FSearchOf();
  end;
  // Thema, Sprache oder Einstellungen können sich geändert haben: alles neu setzen.
  AHeader.Renew;
  AHeader.ShowInfo(Info);
  AHeader.ShowSearch(Settings.WelcomePageSearch and (mSearch <> nil));
  if (mSearch <> nil) and (AHeader.Search <> nil) then
  begin
    mSearch.Attach(AHeader.Search);
  end;
  AttachMenu(AHeader);
end;

procedure TAtlasIdeWelcomeHeaders.AttachMenu(AFrame: TAtlasWelcomeFrame);
var
  mMenu: TAtlasWhatsNewMenu;
begin
  if AFrame = nil then
  begin
    Exit;
  end;
  mMenu := nil;
  if AFrame.PopupMenu is TAtlasWhatsNewMenu then
  begin
    mMenu := TAtlasWhatsNewMenu(AFrame.PopupMenu);
  end;
  if (FAreas.WhatsNew = nil) or not FAreas.WhatsNew.Active then
  begin
    if mMenu <> nil then
    begin
      AFrame.PopupMenu := nil;
      mMenu.Free;
    end;
    Exit;
  end;
  if mMenu = nil then
  begin
    mMenu := TAtlasWhatsNewMenu.Create(AFrame);
    AFrame.PopupMenu := mMenu;
  end;
  mMenu.Source := FAreas.WhatsNew;
end;

procedure TAtlasIdeWelcomeHeaders.UpdateAll;
var
  mBoard: TAtlasWelcomeBoardFrame;
begin
  Fill(IdeHeader);
  mBoard := IdeBoard;
  if mBoard <> nil then
  begin
    mBoard.Header.Visible := Settings.WelcomePageHeader;
    Fill(mBoard.Header);
  end;
  mBoard := TAtlasIdeWelcomeWindow.ExistingBoard;
  if mBoard <> nil then
  begin
    mBoard.Header.Visible := Settings.WelcomePageHeader;
    Fill(mBoard.Header);
  end;
end;

procedure TAtlasIdeWelcomeHeaders.UpdateInfos;
var
  mHeaders: TArray<TAtlasWelcomeHeaderFrame>;
  mHeader: TAtlasWelcomeHeaderFrame;
  mInfo: TAtlasWelcomeHeaderInfo;
begin
  mHeaders := Shown;
  if mHeaders = nil then
  begin
    Exit;
  end;
  mInfo := Info;
  for mHeader in mHeaders do
  begin
    mHeader.ShowInfo(mInfo);
  end;
end;

end.
