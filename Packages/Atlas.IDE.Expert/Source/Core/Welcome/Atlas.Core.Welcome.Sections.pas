unit Atlas.Core.Welcome.Sections;

// Bereiche der Atlas-Willkommensseite (#753), ohne VCL und Open Tools API.
// Jeder Bereich (Zustandskachel #754, Weiterarbeiten #755, Projekte #592 …)
// meldet sich mit Kennung, Titel, Reihenfolge, Vorgabespalte und der Abfrage
// seines Einstellungsschalters an. Die IDE-Schicht zeigt nur Bereiche, deren
// Schalter an ist; ein Bereich mit ausgeschaltetem Schalter wird nicht
// registriert. Ändert sich der Inhalt eines Bereichs oder die Auswahl,
// benachrichtigt TAtlasWelcomeSections ihre Beobachter (aus jedem Thread; die
// Beobachter wechseln selbst in den Hauptthread).

interface

uses
  System.SysUtils,
  System.SyncObjs,
  System.Generics.Collections;

type
{$SCOPEDENUMS ON}
  /// <summary>Spalte im Atlas-Layout; im Fenster „Atlas-Start“ stehen beide untereinander.</summary>
  TAtlasWelcomeColumn = (Left, Right);
{$SCOPEDENUMS OFF}

  TAtlasWelcomeSection = record
    /// <summary>Kennung, z. B. "atlas.state"; siehe TAtlasWelcomeIds.</summary>
    Id: string;
    /// <summary>Überschrift in der Sprache der IDE.</summary>
    Title: string;
    /// <summary>Reihenfolge außerhalb eines Layouts, kleiner zuerst; bei Gleichstand nach Kennung.</summary>
    Order: Integer;
    /// <summary>Spalte, wenn das Layout den Bereich nicht kennt.</summary>
    Column: TAtlasWelcomeColumn;
    /// <summary>Schalter des Bereichs (z. B. welcomePage.state); nil = immer an.</summary>
    Enabled: TFunc<Boolean>;
    function IsEnabled: Boolean;
    class function Create(const AId, ATitle: string; AOrder: Integer; AColumn: TAtlasWelcomeColumn;
      const AEnabled: TFunc<Boolean>): TAtlasWelcomeSection; static;
  end;

  /// <summary>Kennungen der Bereiche und der Plugins auf der Willkommensseite der IDE.</summary>
  TAtlasWelcomeIds = class
  public const
    /// <summary>Kopf mit Symbol, Grußzeile, Version und Kurzstatus (#753).</summary>
    Header = 'atlas.header';
    /// <summary>Alle Atlas-Bereiche im Atlas-Layout als ein Bereich der IDE (#753).</summary>
    Board = 'atlas.board';
    State = 'atlas.state';
    Continue = 'atlas.continue';
    Projects = 'atlas.projects';
    History = 'atlas.history';
    News = 'atlas.news';
    Discover = 'atlas.discover';
    Setup = 'atlas.setup';
    Search = 'atlas.search';
    Unsaved = 'atlas.unsaved';
    Tests = 'atlas.tests';
    Issues = 'atlas.issues';
    Help = 'atlas.help';
    /// <summary>Vorsilbe der Plugin-Kennungen in der IDE.</summary>
    PluginPrefix = 'Atlas.Welcome.';
  public
    /// <summary>"atlas.state" → "Atlas.Welcome.state".</summary>
    class function PluginId(const ASectionId: string): string; static;
    /// <summary>Umkehrung von PluginId; '' für fremde Plugins.</summary>
    class function SectionOf(const APluginId: string): string; static;
  end;

  TAtlasWelcomeSections = class
  private
    FLock: TCriticalSection;
    FItems: TList<TAtlasWelcomeSection>;
    FListeners: TDictionary<Integer, TProc<string>>;
    FNextListener: Integer;
    FVersion: Integer;
    class var FDefault: TAtlasWelcomeSections;
    function IndexOf(const AId: string): Integer;
    procedure Notify(const AId: string);
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Bereiche des Plugins; Tests legen eigene an.</summary>
    class function Default: TAtlasWelcomeSections; static;
    class procedure ReleaseDefault; static;
    /// <summary>Meldet ASection an; ein Bereich mit derselben Kennung wird ersetzt.</summary>
    procedure Add(const ASection: TAtlasWelcomeSection);
    procedure Remove(const AId: string);
    function Find(const AId: string; out ASection: TAtlasWelcomeSection): Boolean;
    /// <summary>Alle angemeldeten Bereiche nach Order, dann Kennung.</summary>
    function All: TArray<TAtlasWelcomeSection>;
    /// <summary>Nur die Bereiche, deren Schalter an ist, in derselben Reihenfolge.</summary>
    function Visible: TArray<TAtlasWelcomeSection>;
    /// <summary>Kennungen von Visible.</summary>
    function VisibleIds: TArray<string>;
    /// <summary>Inhalt des Bereichs AId hat sich geändert (Beobachter erhalten AId).</summary>
    procedure Changed(const AId: string); overload;
    /// <summary>Auswahl oder Schalter geändert (Beobachter erhalten '').</summary>
    procedure Changed; overload;
    /// <summary>Zählt jede Meldung.</summary>
    function Version: Integer;
    /// <summary>Beobachter; AId = geänderter Bereich oder '' für alle.</summary>
    function AddListener(const AListener: TProc<string>): Integer;
    procedure RemoveListener(AHandle: Integer);
  end;

implementation

{ TAtlasWelcomeSection }

function TAtlasWelcomeSection.IsEnabled: Boolean;
begin
  Result := True;
  if Assigned(Enabled) then
    Result := Enabled();
end;

class function TAtlasWelcomeSection.Create(const AId, ATitle: string; AOrder: Integer;
  AColumn: TAtlasWelcomeColumn; const AEnabled: TFunc<Boolean>): TAtlasWelcomeSection;
begin
  Result.Id := AId;
  Result.Title := ATitle;
  Result.Order := AOrder;
  Result.Column := AColumn;
  Result.Enabled := AEnabled;
end;

{ TAtlasWelcomeIds }

class function TAtlasWelcomeIds.PluginId(const ASectionId: string): string;
begin
  Result := ASectionId;
  if SameText(Copy(Result, 1, 6), 'atlas.') then
    Delete(Result, 1, 6);
  Result := PluginPrefix + Result;
end;

class function TAtlasWelcomeIds.SectionOf(const APluginId: string): string;
begin
  Result := '';
  if SameText(Copy(APluginId, 1, Length(PluginPrefix)), PluginPrefix) and (Length(APluginId) > Length(PluginPrefix)) then
    // Kennungen der Bereiche sind klein geschrieben.
    Result := 'atlas.' + LowerCase(Copy(APluginId, Length(PluginPrefix) + 1, MaxInt));
end;

{ TAtlasWelcomeSections }

constructor TAtlasWelcomeSections.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FItems := TList<TAtlasWelcomeSection>.Create;
  FListeners := TDictionary<Integer, TProc<string>>.Create;
end;

destructor TAtlasWelcomeSections.Destroy;
begin
  FListeners.Free;
  FItems.Free;
  FLock.Free;
  inherited;
end;

class function TAtlasWelcomeSections.Default: TAtlasWelcomeSections;
begin
  if FDefault = nil then
    FDefault := TAtlasWelcomeSections.Create;
  Result := FDefault;
end;

class procedure TAtlasWelcomeSections.ReleaseDefault;
begin
  FreeAndNil(FDefault);
end;

function TAtlasWelcomeSections.IndexOf(const AId: string): Integer;
var
  Index: Integer;
begin
  for Index := 0 to FItems.Count - 1 do
    if SameText(FItems[Index].Id, AId) then
      Exit(Index);
  Result := -1;
end;

function Comes(const ALeft, ARight: TAtlasWelcomeSection): Boolean;
begin
  if ALeft.Order <> ARight.Order then
    Result := ALeft.Order < ARight.Order
  else
    Result := CompareText(ALeft.Id, ARight.Id) < 0;
end;

procedure TAtlasWelcomeSections.Add(const ASection: TAtlasWelcomeSection);
var
  Index, Existing: Integer;
begin
  if ASection.Id = '' then
    Exit;
  FLock.Enter;
  try
    Existing := IndexOf(ASection.Id);
    if Existing >= 0 then
      FItems.Delete(Existing);
    Index := 0;
    while (Index < FItems.Count) and not Comes(ASection, FItems[Index]) do
      Inc(Index);
    FItems.Insert(Index, ASection);
  finally
    FLock.Leave;
  end;
  Notify('');
end;

procedure TAtlasWelcomeSections.Remove(const AId: string);
var
  Index: Integer;
begin
  FLock.Enter;
  try
    Index := IndexOf(AId);
    if Index < 0 then
      Exit;
    FItems.Delete(Index);
  finally
    FLock.Leave;
  end;
  Notify('');
end;

function TAtlasWelcomeSections.Find(const AId: string; out ASection: TAtlasWelcomeSection): Boolean;
var
  Index: Integer;
begin
  FLock.Enter;
  try
    Index := IndexOf(AId);
    Result := Index >= 0;
    if Result then
      ASection := FItems[Index]
    else
      // Nicht Default(…): Die Klasse hat selbst eine Methode Default.
      ASection := TAtlasWelcomeSection.Create('', '', 0, TAtlasWelcomeColumn.Left, nil);
  finally
    FLock.Leave;
  end;
end;

function TAtlasWelcomeSections.All: TArray<TAtlasWelcomeSection>;
begin
  FLock.Enter;
  try
    Result := FItems.ToArray;
  finally
    FLock.Leave;
  end;
end;

function TAtlasWelcomeSections.Visible: TArray<TAtlasWelcomeSection>;
var
  Section: TAtlasWelcomeSection;
begin
  Result := nil;
  // Schalter außerhalb der Sperre abfragen: Sie lesen Einstellungen.
  for Section in All do
    if Section.IsEnabled then
      Result := Result + [Section];
end;

function TAtlasWelcomeSections.VisibleIds: TArray<string>;
var
  Section: TAtlasWelcomeSection;
begin
  Result := nil;
  for Section in Visible do
    Result := Result + [Section.Id];
end;

procedure TAtlasWelcomeSections.Changed(const AId: string);
begin
  Notify(AId);
end;

procedure TAtlasWelcomeSections.Changed;
begin
  Notify('');
end;

function TAtlasWelcomeSections.Version: Integer;
begin
  FLock.Enter;
  try
    Result := FVersion;
  finally
    FLock.Leave;
  end;
end;

procedure TAtlasWelcomeSections.Notify(const AId: string);
var
  Listeners: TArray<TProc<string>>;
  Listener: TProc<string>;
begin
  FLock.Enter;
  try
    Inc(FVersion);
    Listeners := FListeners.Values.ToArray;
  finally
    FLock.Leave;
  end;
  // Außerhalb der Sperre: Beobachter dürfen die Bereiche lesen.
  for Listener in Listeners do
    try
      Listener(AId);
    except
      // Ein Fehler im Beobachter darf den meldenden Bereich nicht stören.
      on Exception do
        ;
    end;
end;

function TAtlasWelcomeSections.AddListener(const AListener: TProc<string>): Integer;
begin
  FLock.Enter;
  try
    Inc(FNextListener);
    Result := FNextListener;
    FListeners.Add(Result, AListener);
  finally
    FLock.Leave;
  end;
end;

procedure TAtlasWelcomeSections.RemoveListener(AHandle: Integer);
begin
  FLock.Enter;
  try
    FListeners.Remove(AHandle);
  finally
    FLock.Leave;
  end;
end;

end.
