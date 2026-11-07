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
    /// <summary>Ein Satz für „Seite anpassen“ (#767), wenn TAtlasIdeWelcomeLayouts den Bereich nicht kennt
    /// (Kacheln anderer Module, #1455); '' = keiner.</summary>
    Description: string;
    function IsEnabled: Boolean;
    class function Create(const AId, ATitle: string; AOrder: Integer; AColumn: TAtlasWelcomeColumn;
      const AEnabled: TFunc<Boolean>): TAtlasWelcomeSection; static;
  end;

  /// <summary>Kennungen der Bereiche und der Plugins auf der Willkommensseite der IDE.</summary>
  TAtlasWelcomeIds = class
  public const
    /// <summary>Kopf mit Symbol, Grußzeile, Version und Kurzstatus (#753).</summary>
    cHeader = 'atlas.header';
    /// <summary>Alle Atlas-Bereiche im Atlas-Layout als ein Bereich der IDE (#753).</summary>
    cBoard = 'atlas.board';
    cState = 'atlas.state';
    cContinue = 'atlas.continue';
    cProjects = 'atlas.projects';
    cHistory = 'atlas.history';
    cNews = 'atlas.news';
    cDiscover = 'atlas.discover';
    cSetup = 'atlas.setup';
    cSearch = 'atlas.search';
    cUnsaved = 'atlas.unsaved';
    cTests = 'atlas.tests';
    cIssues = 'atlas.issues';
    /// <summary>Sprint-Kachel mit Burndown (#1277).</summary>
    cSprint = 'atlas.sprint';
    cHelp = 'atlas.help';
    /// <summary>Vorsilbe der Plugin-Kennungen in der IDE.</summary>
    cPluginPrefix = 'Atlas.Welcome.';
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
  begin
    Result := Enabled();
  end;
end;

class function TAtlasWelcomeSection.Create(const AId, ATitle: string; AOrder: Integer;
  AColumn: TAtlasWelcomeColumn; const AEnabled: TFunc<Boolean>): TAtlasWelcomeSection;
begin
  Result.Id := AId;
  Result.Title := ATitle;
  Result.Order := AOrder;
  Result.Column := AColumn;
  Result.Enabled := AEnabled;
  Result.Description := '';
end;

{ TAtlasWelcomeIds }

class function TAtlasWelcomeIds.PluginId(const ASectionId: string): string;
begin
  Result := ASectionId;
  if SameText(Copy(Result, 1, 6), 'atlas.') then
  begin
    Delete(Result, 1, 6);
  end;
  Result := cPluginPrefix + Result;
end;

class function TAtlasWelcomeIds.SectionOf(const APluginId: string): string;
begin
  Result := '';
  if SameText(Copy(APluginId, 1, Length(cPluginPrefix)), cPluginPrefix) and
    (Length(APluginId) > Length(cPluginPrefix)) then
  begin
    // Kennungen der Bereiche sind klein geschrieben.
    Result := 'atlas.' + LowerCase(Copy(APluginId, Length(cPluginPrefix) + 1, MaxInt));
  end;
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
  begin
    FDefault := TAtlasWelcomeSections.Create;
  end;
  Result := FDefault;
end;

class procedure TAtlasWelcomeSections.ReleaseDefault;
begin
  FreeAndNil(FDefault);
end;

function TAtlasWelcomeSections.IndexOf(const AId: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to FItems.Count - 1 do
  begin
    if SameText(FItems[mIndex].Id, AId) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

function Comes(const ALeft, ARight: TAtlasWelcomeSection): Boolean;
begin
  if ALeft.Order <> ARight.Order then
  begin
    Result := ALeft.Order < ARight.Order;
  end
  else
  begin
    Result := CompareText(ALeft.Id, ARight.Id) < 0;
  end;
end;

procedure TAtlasWelcomeSections.Add(const ASection: TAtlasWelcomeSection);
var
  mIndex, mExisting: Integer;
begin
  if ASection.Id = '' then
  begin
    Exit;
  end;
  FLock.Enter;
  try
    mExisting := IndexOf(ASection.Id);
    if mExisting >= 0 then
    begin
      FItems.Delete(mExisting);
    end;
    mIndex := 0;
    while (mIndex < FItems.Count) and not Comes(ASection, FItems[mIndex]) do
    begin
      Inc(mIndex);
    end;
    FItems.Insert(mIndex, ASection);
  finally
    FLock.Leave;
  end;
  Notify('');
end;

procedure TAtlasWelcomeSections.Remove(const AId: string);
var
  mIndex: Integer;
begin
  FLock.Enter;
  try
    mIndex := IndexOf(AId);
    if mIndex < 0 then
    begin
      Exit;
    end;
    FItems.Delete(mIndex);
  finally
    FLock.Leave;
  end;
  Notify('');
end;

function TAtlasWelcomeSections.Find(const AId: string; out ASection: TAtlasWelcomeSection): Boolean;
var
  mIndex: Integer;
begin
  FLock.Enter;
  try
    mIndex := IndexOf(AId);
    Result := mIndex >= 0;
    if Result then
    begin
      ASection := FItems[mIndex];
    end
    else
    begin
      // Nicht Default(…): Die Klasse hat selbst eine Methode Default.
      ASection := TAtlasWelcomeSection.Create('', '', 0, TAtlasWelcomeColumn.Left, nil);
    end;
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
  mSection: TAtlasWelcomeSection;
begin
  Result := nil;
  // Schalter außerhalb der Sperre abfragen: Sie lesen Einstellungen.
  for mSection in All do
  begin
    if mSection.IsEnabled then
    begin
      Result := Result + [mSection];
    end;
  end;
end;

function TAtlasWelcomeSections.VisibleIds: TArray<string>;
var
  mSection: TAtlasWelcomeSection;
begin
  Result := nil;
  for mSection in Visible do
  begin
    Result := Result + [mSection.Id];
  end;
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
  mListeners: TArray<TProc<string>>;
  mListener: TProc<string>;
begin
  FLock.Enter;
  try
    Inc(FVersion);
    mListeners := FListeners.Values.ToArray;
  finally
    FLock.Leave;
  end;
  // Außerhalb der Sperre: Beobachter dürfen die Bereiche lesen.
  for mListener in mListeners do
    try
      mListener(AId);
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
