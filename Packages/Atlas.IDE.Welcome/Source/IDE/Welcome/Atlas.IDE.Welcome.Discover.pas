unit Atlas.IDE.Welcome.Discover;

// Karte „Atlas entdecken“ in der IDE (#757): Quelle der Karte
// (IAtlasDiscoverSource) und Bereich atlas.discover der Willkommensseite.
// - Tipps aus tips.json im Installationsordner, Zählung und Zustand aus der
//   gemeinsamen Zählung TAtlasIdeCommandUsage (#600): usage.json und der
//   Abschnitt "discover" von shortcut-tips.json (gesperrte Tipps, zuletzt
//   gezeigter).
// - Je IDE-Start legt die erste Anfrage die Reihenfolge fest
//   (TAtlasDiscover.Order): noch nie benutzte zuerst, dann die am längsten
//   nicht benutzten; mit tips.usageTracking aus der Reihe nach. Der zuletzt
//   gezeigte Tipp wird gemerkt, der nächste Start beginnt danach.
// - Eingeschaltet heißt: Einstellung des Tipps an (Registry-Name wie bei den
//   Schnellschaltern, #227; eine Auswahl wie WelcomePageWhatsNew gilt außer
//   bei „off“ als an) und Befehl in der Befehlspalette sichtbar (#502 koppelt
//   die Befehle an ihre Einstellungen). Atlas-Tasten ohne Befehl der Palette
//   (Befehlspalette, Vervollständigung, Parameter-Hint) gelten als Befehl mit
//   der Taste aus den Einstellungen. Abgeschaltete Funktionen kommen nie, auch
//   nicht nach „Nächster Tipp“.
// - „Ausprobieren“: Beispieldatei an der Stelle aus tips.json öffnen (mit
//   Hinweis auf das Kürzel in der Meldungsansicht), sonst den Befehl aus
//   "try" bzw. "command" über die Befehlspalette ausführen (zählt dann als
//   Aufruf); der Tipp zur Befehlspalette öffnet sie.
// - „Nicht mehr zeigen“ sperrt den Tipp dauerhaft und speichert sofort.
// - welcomePage.discover aus: kein Bereich, keine Auswahl.
// Protokoll anonym: nur Zahlen, keine Befehle, keine Pfade.

interface

uses
  System.SysUtils,
  Atlas.Core.Commands.Palette,
  Atlas.Core.Commands.Tips,
  Atlas.Core.Welcome.Sections,
  Atlas.Core.Welcome.Discover,
  Atlas.UI.Welcome.Discover;

type
  TAtlasIdeDiscover = class(TInterfacedObject, IAtlasDiscoverSource)
  public const
    /// <summary>Reihenfolge außerhalb des Atlas-Layouts (dort Spalte 2 unter „Neu in Atlas“).</summary>
    cOrder = 60;
  private class var
    FInstance: TAtlasIdeDiscover;
  private
    FCommands: TFunc<TArray<TAtlasCommand>>;
    FRun: TProc<string>;
    FMessage: TProc<string>;
    FQueued: Boolean;
    FQueue: TArray<string>;
    FState: TAtlasDiscoverState;
    FCurrent: string;
    FTitle: string;
    FStarted: Boolean;
    // Befehlsliste für einen Durchgang über alle Tipps (AllowedIds): einmal gebaut statt je Tipp (Start 06.11.2026).
    FSnapshot: TArray<TAtlasCommand>;
    FSnapshotActive: Boolean;
    procedure Report(const AText: string);
    /// <summary>Befehle der Palette; während AllowedIds die einmal gebaute Liste.</summary>
    function Commands: TArray<TAtlasCommand>;
    /// <summary>„Ausprobieren“ für ATip: Beispiel öffnen, sonst den Befehl über die Palette ausführen.</summary>
    procedure TryFound(const ATip: TAtlasTip);
    procedure Changed;
    function Tips: TAtlasTips;
    function Tracking: Boolean;
    function FindCommand(const AId: string; out ACommand: TAtlasCommand): Boolean;
    /// <summary>„Ausprobieren“ kann AId ausführen: Befehl der Palette oder die Befehlspalette selbst.</summary>
    function CanRun(const AId: string): Boolean;
    function IsEnabled(const ATip: TAtlasTip): Boolean;
    /// <summary>Kennungen der Tipps, die gerade in Frage kommen (eingeschaltet, nicht gesperrt).</summary>
    function AllowedIds: TArray<string>;
    procedure EnsureQueue;
    procedure LoadState;
    /// <summary>Zustand in shortcut-tips.json; ANow = sofort speichern.</summary>
    procedure StoreState(ANow: Boolean);
    /// <summary>Den zu zeigenden Tipp bestimmen und als zuletzt gezeigt merken; '' ohne.</summary>
    function Current: string;
    function SamplePath(const ATip: TAtlasTip): string;
  public
    /// <summary>ACommands: sichtbare Atlas-Befehle der Palette mit Taste; ARun: Befehl ausführen;
    /// AMessage: Zeile in die Meldungsansicht.</summary>
    constructor Create(const ACommands: TFunc<TArray<TAtlasCommand>>; const ARun: TProc<string>;
      const AMessage: TProc<string>);
    destructor Destroy; override;
    /// <summary>Bereich und Fabrik anmelden.</summary>
    procedure Start;
    /// <summary>Bereich und Fabrik abmelden (beim Entladen).</summary>
    procedure Stop;
    /// <summary>Nach geänderten Einstellungen: Auswahl und Karte neu (die Reihenfolge des Starts bleibt).</summary>
    procedure Refresh;
    function Section: TAtlasWelcomeSection;
    /// <summary>Gibt es gerade einen Tipp (welcomePage.discover an, eingeschaltete Funktion, nicht gesperrt)?
    /// </summary>
    function Active: Boolean;
    /// <summary>„Gesperrte Tipps wieder zeigen“ (Einstellungen): Sperren aufheben und sofort speichern; ohne
    /// gemeinsame Zählung direkt in der Datei.</summary>
    class procedure UnblockAll; static;
    /// <summary>„Ausprobieren“ über die Dienste von Base (#1455): Befehl AId ausführen, beim Tipp zur
    /// Befehlspalette diese öffnen.</summary>
    class procedure TryCommand(AId: string); static;
    { IAtlasDiscoverSource }
    function Card(out ACard: TAtlasDiscoverCard): Boolean;
    procedure TryTip(const AId: string);
    procedure NextTip(const AId: string);
    procedure BlockTip(const AId: string);
  end;

implementation

uses
  System.Math,
  System.Classes,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Commands.Usage,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Commands.ShortcutTips,
  Atlas.UI.Strings,
  Atlas.UI.Welcome.Strings,
  Atlas.UI.Welcome.Frame,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Commands.Usage,
  Atlas.IDE.Commands.ShortcutTips,
  Atlas.IDE.Results.Commands,
  Atlas.IDE.Foundation.Host;

function English: Boolean;
begin
  Result := TAtlasStrings.Language = TAtlasLanguage.English;
end;

{ TAtlasIdeDiscover }

constructor TAtlasIdeDiscover.Create(const ACommands: TFunc<TArray<TAtlasCommand>>; const ARun: TProc<string>;
  const AMessage: TProc<string>);
begin
  inherited Create;
  FCommands := ACommands;
  FRun := ARun;
  FMessage := AMessage;
  FInstance := Self;
end;

destructor TAtlasIdeDiscover.Destroy;
begin
  if FInstance = Self then
  begin
    FInstance := nil;
  end;
  inherited;
end;

procedure TAtlasIdeDiscover.Start;
begin
  FStarted := True;
  TAtlasWelcomeViews.Register(TAtlasWelcomeIds.cDiscover,
    function(AOwner: TComponent): TAtlasWelcomeSectionFrame
    var
      Frame: TAtlasWelcomeDiscoverFrame;
    begin
      Frame := TAtlasWelcomeDiscoverFrame.Create(AOwner);
      Frame.Source := Self;
      Result := Frame;
    end);
  FTitle := '';
  Refresh;
end;

procedure TAtlasIdeDiscover.Stop;
begin
  FStarted := False;
  TAtlasWelcomeViews.Unregister(TAtlasWelcomeIds.cDiscover);
  TAtlasWelcomeSections.Default.Remove(TAtlasWelcomeIds.cDiscover);
  if FInstance = Self then
  begin
    FInstance := nil;
  end;
end;

function TAtlasIdeDiscover.Section: TAtlasWelcomeSection;
begin
  Result := TAtlasWelcomeSection.Create(TAtlasWelcomeIds.cDiscover, TAtlasDiscoverTexts.TitleText, cOrder,
    TAtlasWelcomeColumn.Right,
    function: Boolean
    begin
      Result := Active;
    end);
end;

procedure TAtlasIdeDiscover.Refresh;
var
  mNext: TAtlasWelcomeSection;
begin
  if not FStarted then
  begin
    Exit;
  end;
  mNext := Section;
  // Nur beim ersten Mal anmelden: Add meldet allen Beobachtern, und die rufen wieder Refresh.
  if mNext.Title <> FTitle then
  begin
    FTitle := mNext.Title;
    TAtlasWelcomeSections.Default.Add(mNext);
    Exit;
  end;
  // Eingeschaltete Funktionen können sich geändert haben: Karte neu.
  TAtlasWelcomeSections.Default.Changed(TAtlasWelcomeIds.cDiscover);
end;

procedure TAtlasIdeDiscover.Changed;
begin
  // Sichtbarkeit (letzter Tipp gesperrt) und Inhalt der Karte.
  TAtlasWelcomeSections.Default.Changed;
  TAtlasWelcomeSections.Default.Changed(TAtlasWelcomeIds.cDiscover);
end;

procedure TAtlasIdeDiscover.Report(const AText: string);
begin
  if Assigned(FMessage) then
  begin
    FMessage(AText);
  end;
end;

function TAtlasIdeDiscover.Tips: TAtlasTips;
begin
  Result := nil;
  if TAtlasIdeCommandUsage.Instance <> nil then
  begin
    Result := TAtlasIdeCommandUsage.Instance.Tips;
  end;
end;

function TAtlasIdeDiscover.Tracking: Boolean;
begin
  Result := TAtlasIdeSettings.Current.TipsUsageTracking and (TAtlasIdeCommandUsage.Instance <> nil);
end;

function TAtlasIdeDiscover.FindCommand(const AId: string; out ACommand: TAtlasCommand): Boolean;
var
  mCommand: TAtlasCommand;
  mKeyText: string;
begin
  ACommand := Default(TAtlasCommand);
  for mCommand in Commands do
  begin
    if SameText(mCommand.Id, AId) then
    begin
      ACommand := mCommand;
      Exit(True);
    end;
  end;
  // Atlas-Taste ohne Befehl der Palette: Taste aus den Einstellungen, nicht über die Palette ausführbar.
  Result := TAtlasIdeShortcutTips.KeyOnlyText(AId, mKeyText);
  if Result then
  begin
    ACommand.Id := AId;
    ACommand.ShortCut := mKeyText;
  end;
end;

function TAtlasIdeDiscover.CanRun(const AId: string): Boolean;
var
  mCommand: TAtlasCommand;
begin
  Result := (AId <> '') and FindCommand(AId, mCommand) and
    (mCommand.IsAtlas or SameText(AId, TAtlasShortcutTips.PaletteCommandId));
end;

function TAtlasIdeDiscover.IsEnabled(const ATip: TAtlasTip): Boolean;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := TAtlasDiscover.IsEnabled(ATip,
    function(AName: string): Boolean
    begin
      // Unbekannter Name: lieber kein Tipp als einer zu einer Funktion, die es so nicht gibt.
      Result := TAtlasDiscover.SettingOn(mSettings, AName);
    end,
    function(AId: string): Boolean
    var
      Command: TAtlasCommand;
    begin
      Result := FindCommand(AId, Command);
    end);
end;

function TAtlasIdeDiscover.Commands: TArray<TAtlasCommand>;
begin
  Result := nil;
  if FSnapshotActive then
  begin
    Result := FSnapshot;
  end
  else if Assigned(FCommands) then
  begin
    Result := FCommands();
  end;
end;

function TAtlasIdeDiscover.AllowedIds: TArray<string>;
var
  mTip: TAtlasTip;
  mOuter: Boolean;
begin
  Result := nil;
  mOuter := not FSnapshotActive;
  if mOuter then
  begin
    FSnapshot := Commands;
    FSnapshotActive := True;
  end;
  try
    for mTip in Tips do
    begin
      if not FState.IsBlocked(mTip.Id) and IsEnabled(mTip) then
      begin
        Result := Result + [mTip.Id];
      end;
    end;
  finally
    if mOuter then
    begin
      FSnapshotActive := False;
      FSnapshot := nil;
    end;
  end;
end;

procedure TAtlasIdeDiscover.LoadState;
begin
  FState := Default(TAtlasDiscoverState);
  if TAtlasIdeCommandUsage.Instance <> nil then
  begin
    FState := TAtlasDiscoverState.Parse(TAtlasIdeCommandUsage.Instance.Usage.Section(TAtlasDiscover.cSectionName));
  end;
end;

procedure TAtlasIdeDiscover.StoreState(ANow: Boolean);
var
  mHolder: TAtlasIdeCommandUsage;
begin
  mHolder := TAtlasIdeCommandUsage.Instance;
  if mHolder = nil then
  begin
    Exit;
  end;
  if mHolder.Usage.Section(TAtlasDiscover.cSectionName) = FState.ToJson then
  begin
    Exit;
  end;
  mHolder.Usage.SetSection(TAtlasDiscover.cSectionName, FState.ToJson);
  if ANow then
  begin
    mHolder.SaveNow;
  end
  else
  begin
    mHolder.Changed;
  end;
end;

procedure TAtlasIdeDiscover.EnsureQueue;
var
  mUsage: TAtlasCommandUsage;
begin
  if FQueued then
  begin
    Exit;
  end;
  FQueued := True;
  LoadState;
  mUsage := nil;
  if TAtlasIdeCommandUsage.Instance <> nil then
  begin
    mUsage := TAtlasIdeCommandUsage.Instance.Usage;
  end;
  FQueue := TAtlasDiscover.Order(Tips, mUsage, FState,
    function(ATip: TAtlasTip): Boolean
    begin
      Result := IsEnabled(ATip);
    end, Tracking);
  // Anonym: nur Zahlen.
  TAtlasGuard.Log(Format('Atlas entdecken (#757): %d von %d Tipps in Frage', [Length(FQueue), Length(Tips)]));
end;

function TAtlasIdeDiscover.Current: string;
begin
  Result := '';
  if not TAtlasIdeSettings.Current.WelcomePageDiscover then
  begin
    Exit;
  end;
  EnsureQueue;
  FCurrent := TAtlasDiscover.Pick(FQueue, AllowedIds, FCurrent);
  Result := FCurrent;
  if (Result <> '') and not SameText(FState.Last, Result) then
  begin
    // Der nächste Start beginnt nach diesem Tipp.
    FState.Last := Result;
    StoreState(False);
  end;
end;

function TAtlasIdeDiscover.Active: Boolean;
begin
  Result := TAtlasIdeSettings.Current.WelcomePage and TAtlasIdeSettings.Current.WelcomePageDiscover and
    (Current <> '');
end;

function TAtlasIdeDiscover.SamplePath(const ATip: TAtlasTip): string;
begin
  Result := '';
  if TAtlasIdeCommandUsage.Instance <> nil then
  begin
    Result := TAtlasTipCatalog.FileIn(TAtlasIdeCommandUsage.Instance.Folder, ATip.Sample);
  end;
  if (Result <> '') and not FileExists(Result) then
  begin
    Result := '';
  end;
end;

function TAtlasIdeDiscover.Card(out ACard: TAtlasDiscoverCard): Boolean;
var
  mId, mImage: string;
  mIndex: Integer;
  mList: TAtlasTips;
  mTip: TAtlasTip;
  mCommand: TAtlasCommand;
  mAllowed, mShown: TArray<string>;
  mUsage: TAtlasCommandUsage;
begin
  ACard := Default(TAtlasDiscoverCard);
  mId := Current;
  mList := Tips;
  mIndex := TAtlasTipCatalog.IndexOf(mList, mId);
  if mIndex < 0 then
  begin
    Exit(False);
  end;
  mTip := mList[mIndex];
  ACard.Id := mTip.Id;
  ACard.Title := mTip.TitleIn(English);
  ACard.Text := mTip.TextIn(English);
  // Tatsächliche Belegung aus der Palette (#520), nicht aus tips.json.
  if FindCommand(mTip.Command, mCommand) then
  begin
    ACard.KeyText := mCommand.ShortCut;
  end;
  mImage := '';
  if TAtlasIdeCommandUsage.Instance <> nil then
  begin
    mImage := TAtlasTipCatalog.FileIn(TAtlasIdeCommandUsage.Instance.Folder, mTip.Image);
  end;
  if (mImage <> '') and FileExists(mImage) then
  begin
    ACard.ImageFile := mImage;
  end;
  mUsage := nil;
  if TAtlasIdeCommandUsage.Instance <> nil then
  begin
    mUsage := TAtlasIdeCommandUsage.Instance.Usage;
  end;
  ACard.Age := TAtlasDiscover.UsageAge(mTip, mUsage, Tracking, Now);
  ACard.CanTry := (SamplePath(mTip) <> '') or CanRun(mTip.TryId);
  mAllowed := AllowedIds;
  mShown := TAtlasDiscover.Effective(FQueue, mAllowed);
  ACard.Position := TAtlasDiscover.IndexIn(mShown, mTip.Id) + 1;
  ACard.Count := Length(mShown);
  Result := True;
end;

procedure TAtlasIdeDiscover.TryFound(const ATip: TAtlasTip);
var
  mFileName: string;
  mCommand: TAtlasCommand;
begin
  mFileName := SamplePath(ATip);
  if mFileName <> '' then
  begin
    // tips.json zählt Zeilen und Spalten ab 1, der Editor ab 0.
    TAtlasIdeResults.Open(mFileName, Max(ATip.Line - 1, 0), Max(ATip.Column - 1, 0));
    if (ATip.Command <> '') and FindCommand(ATip.Command, mCommand) and (mCommand.ShortCut <> '') then
    begin
      Report(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeDiscoverPressKey, [mCommand.ShortCut]));
    end;
  end
  else if ATip.Sample <> '' then
  begin
    Report(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeDiscoverNoSample, [ATip.Sample]));
  end
  else if CanRun(ATip.TryId) and Assigned(FRun) then
  begin
    // Über die Palette: zählt als Aufruf (#600) und steht im Verlauf.
    FRun(ATip.TryId);
  end
  else
  begin
    Report(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeDiscoverNoCommand, [ATip.TryId]));
  end;
end;

procedure TAtlasIdeDiscover.TryTip(const AId: string);
begin
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      mList: TAtlasTips;
      mIndex: Integer;
    begin
      mList := Tips;
      mIndex := TAtlasTipCatalog.IndexOf(mList, AId);
      if mIndex >= 0 then
      begin
        TryFound(mList[mIndex]);
      end;
    end);
end;

procedure TAtlasIdeDiscover.NextTip(const AId: string);
begin
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      Next: string;
    begin
      EnsureQueue;
      Next := TAtlasDiscover.NextAfter(FQueue, AllowedIds, AId);
      if Next = '' then
      begin
        Exit;
      end;
      FCurrent := Next;
      FState.Last := Next;
      StoreState(False);
      Changed;
    end);
end;

procedure TAtlasIdeDiscover.BlockTip(const AId: string);
begin
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      Next: string;
    begin
      EnsureQueue;
      // Erst den nächsten bestimmen: Nach dem Sperren steht AId nicht mehr unter den erlaubten.
      Next := TAtlasDiscover.NextAfter(FQueue, AllowedIds, AId);
      FState.Block(AId);
      if SameText(Next, AId) then
      begin
        Next := '';
      end;
      FCurrent := Next;
      if Next <> '' then
      begin
        FState.Last := Next;
      end;
      // Dauerhaft: sofort speichern, auch gegen einen Absturz.
      StoreState(True);
      TAtlasGuard.Log('Atlas entdecken (#757): Tipp gesperrt');
      Changed;
    end);
end;

class procedure TAtlasIdeDiscover.UnblockAll;
var
  mUsage: TAtlasCommandUsage;
  mState: TAtlasDiscoverState;
begin
  if TAtlasIdeCommandUsage.Instance <> nil then
  begin
    mUsage := TAtlasIdeCommandUsage.Instance.Usage;
    mState := TAtlasDiscoverState.Parse(mUsage.Section(TAtlasDiscover.cSectionName));
    mState.Blocked := nil;
    mUsage.SetSection(TAtlasDiscover.cSectionName, mState.ToJson);
    TAtlasIdeCommandUsage.Instance.SaveNow;
    if FInstance <> nil then
    begin
      FInstance.FState.Blocked := nil;
      FInstance.Changed;
    end;
  end
  else
  begin
    mUsage := TAtlasCommandUsage.Create;
    try
      mUsage.LoadFromFiles(TAtlasIdeCommandUsage.TipsFile, TAtlasIdeCommandUsage.UsageFile);
      mState := TAtlasDiscoverState.Parse(mUsage.Section(TAtlasDiscover.cSectionName));
      mState.Blocked := nil;
      mUsage.SetSection(TAtlasDiscover.cSectionName, mState.ToJson);
      mUsage.SaveToFiles(TAtlasIdeCommandUsage.TipsFile, TAtlasIdeCommandUsage.UsageFile);
    finally
      mUsage.Free;
    end;
  end;
  TAtlasGuard.Log('Atlas entdecken (#757): Sperren aufgehoben');
end;

class procedure TAtlasIdeDiscover.TryCommand(AId: string);
begin
  if SameText(AId, TAtlasShortcutTips.PaletteCommandId) then
  begin
    TAtlasIdeHost.ShowPalette;
  end
  else
  begin
    TAtlasIdeHost.ExecuteCommand(AId);
  end;
end;

end.
