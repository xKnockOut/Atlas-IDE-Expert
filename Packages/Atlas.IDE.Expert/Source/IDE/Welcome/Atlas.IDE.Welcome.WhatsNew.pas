unit Atlas.IDE.Welcome.WhatsNew;

// Karte „Neu in Atlas“ in der IDE (#756): Quelle der Karte
// (IAtlasWhatsNewSource) und Bereich atlas.news der Willkommensseite.
// - whatsnew.json liegt neben den BPLs oder eine Ebene darüber (Release-Paket:
//   <Ziel>\Win32\…bpl, <Ziel>\whatsnew.json); Beispieldateien relativ dazu.
// - Gesehene Version: WhatsNewSeen in den Plugin-Einstellungen (Registry).
//   Beim ersten Start wird die aktuelle Version gemerkt, es gibt dann nichts
//   Ungelesenes. „Gelesen“ merkt die aktuelle Version.
// - welcomePage.whatsNew: off zeigt nichts (auch kein Kontextmenü), afterUpdate
//   zeigt nach einem Versionswechsel die übersprungenen Versionen, always
//   zusätzlich danach die Neuerungen der aktuellen Version.
// - „Neuigkeiten dieser Version zeigen“ und „Alle Versionen“ (Kontextmenü,
//   Befehlspalette) gelten bis „Schließen“ oder zum Neustart.
// - Der Schalter einer Zeile setzt die Einstellung über die gespeicherten
//   Werte (wie die Optionsseite, #227), das Tastenkürzel kommt aus der
//   Tasten-Einstellung der Zeile.

interface

uses
  System.SysUtils,
  Atlas.Core.Welcome.WhatsNew,
  Atlas.Core.Welcome.Sections,
  Atlas.UI.Welcome.WhatsNew;

type
  TAtlasIdeWhatsNew = class(TInterfacedObject, IAtlasWhatsNewSource)
  public const
    /// <summary>Reihenfolge außerhalb des Atlas-Layouts; nach einem Update ganz vorn.</summary>
    Order = 50;
  private
    FVersions: TAtlasWhatsNewVersions;
    FFolder: string;
    FSeen: string;
    FCurrent: string;
    FManual: Boolean;
    FManualView: TAtlasWhatsNewView;
    FTitle: string;
    FOrderShown: Integer;
    FCommandExists: TFunc<string, Boolean>;
    FRun: TProc<string>;
    FMessage: TProc<string>;
    procedure Report(const AText: string);
    procedure Changed;
    function Mode: TAtlasWhatsNewMode;
  public
    /// <summary>ACommandExists/ARun: Atlas-Befehle der Palette; AMessage: Zeile in die Meldungsansicht.</summary>
    constructor Create(const ACommandExists: TFunc<string, Boolean>; const ARun: TProc<string>;
      const AMessage: TProc<string>);
    /// <summary>whatsnew.json lesen und den Bereich anmelden.</summary>
    procedure Start;
    /// <summary>Bereich und Fabrik abmelden (beim Entladen).</summary>
    procedure Stop;
    /// <summary>Titel und Reihenfolge des Bereichs nachführen (nach jeder Änderung der Einstellungen).</summary>
    procedure Refresh;
    /// <summary>Einträge an die laufende Version anhängen (#767: neue Bereiche im eigenen Layout); doppelte
    /// Titel fallen weg.</summary>
    procedure Announce(const AItems: TArray<TAtlasWhatsNewItem>);
    /// <summary>Steht die Karte oben (Ungelesenes nach einem Update)?</summary>
    function OnTop: Boolean;
    /// <summary>Kontextmenü und Befehle: nur, wenn welcomePage.whatsNew nicht off ist.</summary>
    function Active: Boolean;
    function Section: TAtlasWelcomeSection;
    { IAtlasWhatsNewSource }
    function View: TAtlasWhatsNewView;
    function Versions: TAtlasWhatsNewVersions;
    function SwitchOf(const ASetting: string): TAtlasWhatsNewSwitch;
    function KeyText(const AKey: string): string;
    function CanTry(const AItem: TAtlasWhatsNewItem): Boolean;
    procedure SetSwitch(const ASetting: string; AOn: Boolean);
    procedure TryItem(const AItem: TAtlasWhatsNewItem);
    procedure Dismiss;
    procedure Show(AView: TAtlasWhatsNewView);
    /// <summary>Ordner mit whatsnew.json: neben dem Plugin oder eine Ebene darüber; '' ohne Datei.</summary>
    class function FindFolder(const APluginDir: string): string; static;
    /// <summary>Beispieldatei ASample relativ zu AFolder; '' bei absolutem Pfad oder „..“.</summary>
    class function SamplePath(const AFolder, ASample: string): string; static;
  end;

implementation

uses
  Atlas.Core.Diagnostics.MainThread,
  System.Classes,
  System.IOUtils,
  Vcl.Menus,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Product.Version,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.History,
  Atlas.Core.Settings.QuickToggles,
  Atlas.UI.Strings,
  Atlas.UI.Welcome.Frame,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Results.Commands;

/// <summary>Textdatei als UTF-8 ohne Byte-Order-Mark; '' bei Fehler.</summary>
function ReadText(const AFileName: string): string;
begin
  Result := '';
  try
    Result := TFile.ReadAllText(AFileName, TEncoding.UTF8);
  except
    on Exception do
      Exit('');
  end;
  if (Result <> '') and (Result[1] = #$FEFF) then
    Delete(Result, 1, 1);
end;

{ TAtlasIdeWhatsNew }

constructor TAtlasIdeWhatsNew.Create(const ACommandExists: TFunc<string, Boolean>; const ARun: TProc<string>;
  const AMessage: TProc<string>);
begin
  inherited Create;
  FCommandExists := ACommandExists;
  FRun := ARun;
  FMessage := AMessage;
  FCurrent := TAtlasPluginVersion.Version;
  FManualView := TAtlasWhatsNewView.Hidden;
  FOrderShown := -1;
end;

class function TAtlasIdeWhatsNew.FindFolder(const APluginDir: string): string;
var
  Candidate: string;
begin
  Result := '';
  if APluginDir = '' then
    Exit;
  Candidate := IncludeTrailingPathDelimiter(APluginDir);
  if FileExists(Candidate + TAtlasWhatsNew.FileName) then
    Exit(Candidate);
  Candidate := IncludeTrailingPathDelimiter(ExpandFileName(Candidate + '..'));
  if FileExists(Candidate + TAtlasWhatsNew.FileName) then
    Result := Candidate;
end;

class function TAtlasIdeWhatsNew.SamplePath(const AFolder, ASample: string): string;
begin
  Result := '';
  // Nur Dateien im Installationsordner: whatsnew.json ist Teil der Installation, aber kein Ort für fremde Pfade.
  if (AFolder = '') or (ASample = '') or (Pos('..', ASample) > 0) or (Pos(':', ASample) > 0) or
    CharInSet(ASample[1], ['\', '/']) then
    Exit;
  Result := IncludeTrailingPathDelimiter(AFolder) + StringReplace(ASample, '/', PathDelim, [rfReplaceAll]);
end;

procedure TAtlasIdeWhatsNew.Start;
var
  Stored: TAtlasPluginSettings;
  Current: string;
begin
  FFolder := FindFolder(ExtractFilePath(GetModuleName(HInstance)));
  FVersions := nil;
  if FFolder <> '' then
    FVersions := TAtlasWhatsNew.Parse(ReadText(FFolder + TAtlasWhatsNew.FileName));
  Stored := TAtlasIdeSettings.Stored;
  FSeen := Stored.WhatsNewSeen;
  if TAtlasWhatsNew.SeenAfterStart(FSeen, FCurrent) <> FSeen then
  begin
    // Erste Installation: nichts Ungelesenes. Gespeichert wird nach dem Laden des Plugins.
    FSeen := TAtlasWhatsNew.SeenAfterStart(FSeen, FCurrent);
    Current := FCurrent;
    TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
      procedure
      var
        Next: TAtlasPluginSettings;
      begin
        Next := TAtlasIdeSettings.Stored;
        if Next.WhatsNewSeen <> '' then
          Exit;
        Next.WhatsNewSeen := Current;
        TAtlasIdeSettings.Update(Next);
      end);
  end;
  TAtlasWelcomeViews.Register(TAtlasWelcomeIds.News,
    function(AOwner: TComponent): TAtlasWelcomeSectionFrame
    var
      Frame: TAtlasWelcomeWhatsNewFrame;
    begin
      Frame := TAtlasWelcomeWhatsNewFrame.Create(AOwner);
      Frame.Source := Self;
      Result := Frame;
    end);
  Refresh;
end;

procedure TAtlasIdeWhatsNew.Stop;
begin
  TAtlasWelcomeViews.Unregister(TAtlasWelcomeIds.News);
  TAtlasWelcomeSections.Default.Remove(TAtlasWelcomeIds.News);
end;

function TAtlasIdeWhatsNew.Mode: TAtlasWhatsNewMode;
begin
  Result := TAtlasWhatsNew.ModeOf(TAtlasIdeSettings.Current.WelcomePageWhatsNew);
end;

function TAtlasIdeWhatsNew.Active: Boolean;
begin
  Result := Mode <> TAtlasWhatsNewMode.Off;
end;

function TAtlasIdeWhatsNew.View: TAtlasWhatsNewView;
begin
  if not Active then
    Exit(TAtlasWhatsNewView.Hidden);
  if FManual then
    Exit(FManualView);
  Result := TAtlasWhatsNew.ViewFor(Mode, FVersions, FSeen, FCurrent);
end;

function TAtlasIdeWhatsNew.Versions: TAtlasWhatsNewVersions;
begin
  Result := TAtlasWhatsNew.VersionsFor(View, FVersions, FSeen, FCurrent);
end;

function TAtlasIdeWhatsNew.OnTop: Boolean;
begin
  Result := View = TAtlasWhatsNewView.Unread;
end;

function TAtlasIdeWhatsNew.Section: TAtlasWelcomeSection;
var
  Position: Integer;
begin
  Position := Order;
  if OnTop then
    Position := 0;
  Result := TAtlasWelcomeSection.Create(TAtlasWelcomeIds.News,
    TAtlasWelcomeWhatsNewFrame.TitleFor(View, Versions), Position, TAtlasWelcomeColumn.Right,
    function: Boolean
    begin
      Result := View <> TAtlasWhatsNewView.Hidden;
    end);
end;

procedure TAtlasIdeWhatsNew.Refresh;
var
  Next: TAtlasWelcomeSection;
begin
  Next := Section;
  // Nur bei Änderung neu anmelden: Add meldet allen Beobachtern, und die rufen wieder Refresh.
  if (Next.Title = FTitle) and (Next.Order = FOrderShown) then
    Exit;
  FTitle := Next.Title;
  FOrderShown := Next.Order;
  TAtlasWelcomeSections.Default.Add(Next);
end;

procedure TAtlasIdeWhatsNew.Announce(const AItems: TArray<TAtlasWhatsNewItem>);
begin
  if Length(AItems) = 0 then
    Exit;
  FVersions := TAtlasWhatsNew.WithItems(FVersions, FCurrent, AItems);
  Changed;
end;

procedure TAtlasIdeWhatsNew.Changed;
begin
  Refresh;
  // Auswahl (sichtbar, oben) und Inhalt der Karte.
  TAtlasWelcomeSections.Default.Changed;
  TAtlasWelcomeSections.Default.Changed(TAtlasWelcomeIds.News);
end;

procedure TAtlasIdeWhatsNew.Report(const AText: string);
begin
  if Assigned(FMessage) then
    FMessage(AText);
end;

function TAtlasIdeWhatsNew.SwitchOf(const ASetting: string): TAtlasWhatsNewSwitch;
var
  Value: Boolean;
begin
  // Gespeicherte Werte wie die Optionsseite: Der Schalter ändert genau diese.
  Result := TAtlasWhatsNewSwitch.None;
  if not TAtlasQuickToggles.GetFlag(TAtlasIdeSettings.Stored, ASetting, Value) then
    Exit;
  if Value then
    Result := TAtlasWhatsNewSwitch.On
  else
    Result := TAtlasWhatsNewSwitch.Off;
end;

function TAtlasIdeWhatsNew.KeyText(const AKey: string): string;
var
  Store: IAtlasMemorySettingsStore;
begin
  Result := '';
  Store := TAtlasMemorySettingsStore.FromSettings(TAtlasIdeSettings.Current);
  if Store.HasInteger(AKey) and (Store.ReadInteger(AKey, 0) > 0) then
    Result := ShortCutToText(TShortCut(Store.ReadInteger(AKey, 0)));
end;

function TAtlasIdeWhatsNew.CanTry(const AItem: TAtlasWhatsNewItem): Boolean;
begin
  if AItem.Command <> '' then
    Exit(Assigned(FCommandExists) and FCommandExists(AItem.Command));
  Result := (SamplePath(FFolder, AItem.Sample) <> '') and FileExists(SamplePath(FFolder, AItem.Sample));
end;

procedure TAtlasIdeWhatsNew.SetSwitch(const ASetting: string; AOn: Boolean);
begin
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      Next: TAtlasPluginSettings;
    begin
      Next := TAtlasIdeSettings.Stored;
      if not TAtlasQuickToggles.SetFlag(Next, ASetting, AOn) then
        Exit;
      // Update meldet OnChanged: Die Funktion wirkt sofort, die Optionsseite zeigt denselben Wert.
      TAtlasIdeSettings.Update(Next);
      TAtlasWelcomeSections.Default.Changed(TAtlasWelcomeIds.News);
    end);
end;

procedure TAtlasIdeWhatsNew.TryItem(const AItem: TAtlasWhatsNewItem);
begin
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      FileName: string;
      Line: Integer;
    begin
      if AItem.Command <> '' then
      begin
        if Assigned(FCommandExists) and FCommandExists(AItem.Command) and Assigned(FRun) then
          FRun(AItem.Command)
        else
          Report(TAtlasStrings.Fmt(TAtlasTextId.WelcomeNewsNoCommand, [AItem.Command]));
        Exit;
      end;
      FileName := SamplePath(FFolder, AItem.Sample);
      if (FileName = '') or not FileExists(FileName) then
      begin
        Report(TAtlasStrings.Fmt(TAtlasTextId.WelcomeNewsNoSample, [AItem.Sample]));
        Exit;
      end;
      // whatsnew.json zählt Zeilen ab 1, der Editor ab 0.
      Line := AItem.Line - 1;
      if Line < 0 then
        Line := 0;
      TAtlasIdeResults.Open(FileName, Line, 0);
    end);
end;

procedure TAtlasIdeWhatsNew.Dismiss;
begin
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      Next: TAtlasPluginSettings;
    begin
      if View = TAtlasWhatsNewView.Unread then
      begin
        // „Gelesen“: Die aktuelle Version gilt als gesehen, auch nach einem Neustart.
        FSeen := FCurrent;
        FManual := False;
        Next := TAtlasIdeSettings.Stored;
        Next.WhatsNewSeen := FCurrent;
        TAtlasIdeSettings.Update(Next);
      end
      else
      begin
        // „Schließen“: bis zum nächsten Start ausgeblendet.
        FManual := True;
        FManualView := TAtlasWhatsNewView.Hidden;
      end;
      Changed;
    end);
end;

procedure TAtlasIdeWhatsNew.Show(AView: TAtlasWhatsNewView);
begin
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      if not Active then
        Exit;
      if Length(TAtlasWhatsNew.VersionsFor(AView, FVersions, FSeen, FCurrent)) = 0 then
      begin
        Report(TAtlasStrings.Fmt(TAtlasTextId.WelcomeNewsMissing, [TAtlasWhatsNew.FileName]));
        Exit;
      end;
      FManual := True;
      FManualView := AView;
      Changed;
    end);
end;

end.
