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
    Order = 60;
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
    procedure Report(const AText: string);
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
    { IAtlasDiscoverSource }
    function Card(out ACard: TAtlasDiscoverCard): Boolean;
    procedure TryTip(const AId: string);
    procedure NextTip(const AId: string);
    procedure BlockTip(const AId: string);
  end;

implementation

uses
  System.Classes,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Commands.Usage,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Commands.ShortcutTips,
  Atlas.UI.Strings,
  Atlas.UI.Welcome.Frame,
  Atlas.IDE.Settings.Store,
  Atlas.IDE.Commands.Usage,
  Atlas.IDE.Commands.ShortcutTips,
  Atlas.IDE.Results.Commands;

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
    FInstance := nil;
  inherited;
end;

procedure TAtlasIdeDiscover.Start;
begin
  FStarted := True;
  TAtlasWelcomeViews.Register(TAtlasWelcomeIds.Discover,
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
  TAtlasWelcomeViews.Unregister(TAtlasWelcomeIds.Discover);
  TAtlasWelcomeSections.Default.Remove(TAtlasWelcomeIds.Discover);
  if FInstance = Self then
    FInstance := nil;
end;

function TAtlasIdeDiscover.Section: TAtlasWelcomeSection;
begin
  Result := TAtlasWelcomeSection.Create(TAtlasWelcomeIds.Discover, TAtlasWelcomeDiscoverFrame.TitleText, Order,
    TAtlasWelcomeColumn.Right,
    function: Boolean
    begin
      Result := Active;
    end);
end;

procedure TAtlasIdeDiscover.Refresh;
var
  Next: TAtlasWelcomeSection;
begin
  if not FStarted then
    Exit;
  Next := Section;
  // Nur beim ersten Mal anmelden: Add meldet allen Beobachtern, und die rufen wieder Refresh.
  if Next.Title <> FTitle then
  begin
    FTitle := Next.Title;
    TAtlasWelcomeSections.Default.Add(Next);
    Exit;
  end;
  // Eingeschaltete Funktionen können sich geändert haben: Karte neu.
  TAtlasWelcomeSections.Default.Changed(TAtlasWelcomeIds.Discover);
end;

procedure TAtlasIdeDiscover.Changed;
begin
  // Sichtbarkeit (letzter Tipp gesperrt) und Inhalt der Karte.
  TAtlasWelcomeSections.Default.Changed;
  TAtlasWelcomeSections.Default.Changed(TAtlasWelcomeIds.Discover);
end;

procedure TAtlasIdeDiscover.Report(const AText: string);
begin
  if Assigned(FMessage) then
    FMessage(AText);
end;

function TAtlasIdeDiscover.Tips: TAtlasTips;
begin
  Result := nil;
  if TAtlasIdeCommandUsage.Instance <> nil then
    Result := TAtlasIdeCommandUsage.Instance.Tips;
end;

function TAtlasIdeDiscover.Tracking: Boolean;
begin
  Result := TAtlasIdeSettings.Current.TipsUsageTracking and (TAtlasIdeCommandUsage.Instance <> nil);
end;

function TAtlasIdeDiscover.FindCommand(const AId: string; out ACommand: TAtlasCommand): Boolean;
var
  Command: TAtlasCommand;
  KeyText: string;
begin
  ACommand := Default(TAtlasCommand);
  if Assigned(FCommands) then
    for Command in FCommands() do
      if SameText(Command.Id, AId) then
      begin
        ACommand := Command;
        Exit(True);
      end;
  // Atlas-Taste ohne Befehl der Palette: Taste aus den Einstellungen, nicht über die Palette ausführbar.
  Result := TAtlasIdeShortcutTips.KeyOnlyText(AId, KeyText);
  if Result then
  begin
    ACommand.Id := AId;
    ACommand.ShortCut := KeyText;
  end;
end;

function TAtlasIdeDiscover.CanRun(const AId: string): Boolean;
var
  Command: TAtlasCommand;
begin
  Result := (AId <> '') and FindCommand(AId, Command) and
    (Command.IsAtlas or SameText(AId, TAtlasShortcutTips.PaletteCommandId));
end;

function TAtlasIdeDiscover.IsEnabled(const ATip: TAtlasTip): Boolean;
var
  Settings: TAtlasPluginSettings;
begin
  Settings := TAtlasIdeSettings.Current;
  Result := TAtlasDiscover.IsEnabled(ATip,
    function(AName: string): Boolean
    begin
      // Unbekannter Name: lieber kein Tipp als einer zu einer Funktion, die es so nicht gibt.
      Result := TAtlasDiscover.SettingOn(Settings, AName);
    end,
    function(AId: string): Boolean
    var
      Command: TAtlasCommand;
    begin
      Result := FindCommand(AId, Command);
    end);
end;

function TAtlasIdeDiscover.AllowedIds: TArray<string>;
var
  Tip: TAtlasTip;
begin
  Result := nil;
  for Tip in Tips do
    if not FState.IsBlocked(Tip.Id) and IsEnabled(Tip) then
      Result := Result + [Tip.Id];
end;

procedure TAtlasIdeDiscover.LoadState;
begin
  FState := Default(TAtlasDiscoverState);
  if TAtlasIdeCommandUsage.Instance <> nil then
    FState := TAtlasDiscoverState.Parse(TAtlasIdeCommandUsage.Instance.Usage.Section(TAtlasDiscover.SectionName));
end;

procedure TAtlasIdeDiscover.StoreState(ANow: Boolean);
var
  Holder: TAtlasIdeCommandUsage;
begin
  Holder := TAtlasIdeCommandUsage.Instance;
  if Holder = nil then
    Exit;
  if Holder.Usage.Section(TAtlasDiscover.SectionName) = FState.ToJson then
    Exit;
  Holder.Usage.SetSection(TAtlasDiscover.SectionName, FState.ToJson);
  if ANow then
    Holder.SaveNow
  else
    Holder.Changed;
end;

procedure TAtlasIdeDiscover.EnsureQueue;
var
  Usage: TAtlasCommandUsage;
begin
  if FQueued then
    Exit;
  FQueued := True;
  LoadState;
  Usage := nil;
  if TAtlasIdeCommandUsage.Instance <> nil then
    Usage := TAtlasIdeCommandUsage.Instance.Usage;
  FQueue := TAtlasDiscover.Order(Tips, Usage, FState,
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
    Exit;
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
    Result := TAtlasTipCatalog.FileIn(TAtlasIdeCommandUsage.Instance.Folder, ATip.Sample);
  if (Result <> '') and not FileExists(Result) then
    Result := '';
end;

function TAtlasIdeDiscover.Card(out ACard: TAtlasDiscoverCard): Boolean;
var
  Id, Image: string;
  Index: Integer;
  List: TAtlasTips;
  Tip: TAtlasTip;
  Command: TAtlasCommand;
  Allowed, Shown: TArray<string>;
  Usage: TAtlasCommandUsage;
begin
  ACard := Default(TAtlasDiscoverCard);
  Id := Current;
  List := Tips;
  Index := TAtlasTipCatalog.IndexOf(List, Id);
  if Index < 0 then
    Exit(False);
  Tip := List[Index];
  ACard.Id := Tip.Id;
  ACard.Title := Tip.TitleIn(English);
  ACard.Text := Tip.TextIn(English);
  // Tatsächliche Belegung aus der Palette (#520), nicht aus tips.json.
  if FindCommand(Tip.Command, Command) then
    ACard.KeyText := Command.ShortCut;
  Image := '';
  if TAtlasIdeCommandUsage.Instance <> nil then
    Image := TAtlasTipCatalog.FileIn(TAtlasIdeCommandUsage.Instance.Folder, Tip.Image);
  if (Image <> '') and FileExists(Image) then
    ACard.ImageFile := Image;
  Usage := nil;
  if TAtlasIdeCommandUsage.Instance <> nil then
    Usage := TAtlasIdeCommandUsage.Instance.Usage;
  ACard.Age := TAtlasDiscover.UsageAge(Tip, Usage, Tracking, Now);
  ACard.CanTry := (SamplePath(Tip) <> '') or CanRun(Tip.TryId);
  Allowed := AllowedIds;
  Shown := TAtlasDiscover.Effective(FQueue, Allowed);
  ACard.Position := TAtlasDiscover.IndexIn(Shown, Tip.Id) + 1;
  ACard.Count := Length(Shown);
  Result := True;
end;

procedure TAtlasIdeDiscover.TryTip(const AId: string);
begin
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      Index, Line, Column: Integer;
      List: TAtlasTips;
      Tip: TAtlasTip;
      FileName: string;
      Command: TAtlasCommand;
      HasCommand: Boolean;
    begin
      List := Tips;
      Index := TAtlasTipCatalog.IndexOf(List, AId);
      if Index < 0 then
        Exit;
      Tip := List[Index];
      HasCommand := (Tip.Command <> '') and FindCommand(Tip.Command, Command);
      FileName := SamplePath(Tip);
      if FileName <> '' then
      begin
        // tips.json zählt Zeilen und Spalten ab 1, der Editor ab 0.
        Line := Tip.Line - 1;
        if Line < 0 then
          Line := 0;
        Column := Tip.Column - 1;
        if Column < 0 then
          Column := 0;
        TAtlasIdeResults.Open(FileName, Line, Column);
        if HasCommand and (Command.ShortCut <> '') then
          Report(TAtlasStrings.Fmt(TAtlasTextId.WelcomeDiscoverPressKey, [Command.ShortCut]));
        Exit;
      end;
      if Tip.Sample <> '' then
      begin
        Report(TAtlasStrings.Fmt(TAtlasTextId.WelcomeDiscoverNoSample, [Tip.Sample]));
        Exit;
      end;
      if CanRun(Tip.TryId) and Assigned(FRun) then
        // Über die Palette: zählt als Aufruf (#600) und steht im Verlauf.
        FRun(Tip.TryId)
      else
        Report(TAtlasStrings.Fmt(TAtlasTextId.WelcomeDiscoverNoCommand, [Tip.TryId]));
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
        Exit;
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
        Next := '';
      FCurrent := Next;
      if Next <> '' then
        FState.Last := Next;
      // Dauerhaft: sofort speichern, auch gegen einen Absturz.
      StoreState(True);
      TAtlasGuard.Log('Atlas entdecken (#757): Tipp gesperrt');
      Changed;
    end);
end;

class procedure TAtlasIdeDiscover.UnblockAll;
var
  Usage: TAtlasCommandUsage;
  State: TAtlasDiscoverState;
begin
  if TAtlasIdeCommandUsage.Instance <> nil then
  begin
    Usage := TAtlasIdeCommandUsage.Instance.Usage;
    State := TAtlasDiscoverState.Parse(Usage.Section(TAtlasDiscover.SectionName));
    State.Blocked := nil;
    Usage.SetSection(TAtlasDiscover.SectionName, State.ToJson);
    TAtlasIdeCommandUsage.Instance.SaveNow;
    if FInstance <> nil then
    begin
      FInstance.FState.Blocked := nil;
      FInstance.Changed;
    end;
  end
  else
  begin
    Usage := TAtlasCommandUsage.Create;
    try
      Usage.LoadFromFiles(TAtlasIdeCommandUsage.TipsFile, TAtlasIdeCommandUsage.UsageFile);
      State := TAtlasDiscoverState.Parse(Usage.Section(TAtlasDiscover.SectionName));
      State.Blocked := nil;
      Usage.SetSection(TAtlasDiscover.SectionName, State.ToJson);
      Usage.SaveToFiles(TAtlasIdeCommandUsage.TipsFile, TAtlasIdeCommandUsage.UsageFile);
    finally
      Usage.Free;
    end;
  end;
  TAtlasGuard.Log('Atlas entdecken (#757): Sperren aufgehoben');
end;

end.
