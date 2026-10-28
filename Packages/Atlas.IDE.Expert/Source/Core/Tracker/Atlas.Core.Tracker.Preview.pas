unit Atlas.Core.Tracker.Preview;

// Entscheidungen des Fensters „Atlas-Issue“ (#1264) ohne VCL und Open Tools
// API, damit sie ohne Fenster testbar sind:
// - TAtlasIssueHistory: Verlauf Zurück/Vor (Alt+Links/Alt+Rechts), höchstens
//   MaxEntries Einträge; ein neues Issue verwirft die Vor-Einträge.
// - TAtlasIssuePreview.Badges: Felder als Abzeichen in fester Reihenfolge
//   (Zustand, Priorität, Typ, Zuständig, Sprint/Meilenstein, Labels, erstellt,
//   aktualisiert).
// - Age: Zeitabstand für „vor 3 Std.“ (Tooltip mit der absoluten Zeit).
// - Kommentare: neueste unten, die ShownComments neuesten offen, ältere
//   eingeklappt („12 ältere Kommentare“). Aus einer Meldung (#1271) öffnet
//   das Fenster am ersten neuen Kommentar (CommentAt); liegt er bei den
//   eingeklappten, klappen sie auf.
// - Bilder: relative Adressen (YouTrack) sind Namen von Anhängen; geladen
//   wird nur, was beim Server des Tokens liegt (sonst ginge eine Anfrage an
//   einen Rechner aus dem Issue-Text). Anderes bleibt ein Link.
// - Fehler: Art und Befehl zum Beheben (Token hinterlegen, Einstellungen,
//   Im Browser öffnen, erneut versuchen).

interface

uses
  System.SysUtils,
  Atlas.Core.Ci.Contract,
  Atlas.Core.Tracker.Contract;

type
  TAtlasIssueHistoryEntry = record
    Target: TAtlasTrackerTarget;
    Key: string;
    class function Create(const ATarget: TAtlasTrackerTarget; const AKey: string): TAtlasIssueHistoryEntry; static;
    function SameAs(const AOther: TAtlasIssueHistoryEntry): Boolean;
  end;

  TAtlasIssueHistory = class
  public const
    MaxEntries = 20;
  private
    FEntries: TArray<TAtlasIssueHistoryEntry>;
    FIndex: Integer;
  public
    constructor Create;
    /// <summary>Neues Issue: hinter dem aktuellen anhängen (Vor-Einträge entfallen); dasselbe wie das aktuelle
    /// ändert nichts.</summary>
    procedure Visit(const AEntry: TAtlasIssueHistoryEntry);
    function CanBack: Boolean;
    function CanForward: Boolean;
    function GoBack(out AEntry: TAtlasIssueHistoryEntry): Boolean;
    function GoForward(out AEntry: TAtlasIssueHistoryEntry): Boolean;
    function Current(out AEntry: TAtlasIssueHistoryEntry): Boolean;
    function Count: Integer;
    procedure Clear;
  end;

{$SCOPEDENUMS ON}
  TAtlasIssueBadgeKind = (State, Priority, Kind, Assignee, Sprint, LabelName, Created, Updated);
  TAtlasIssueAgeUnit = (JustNow, Minutes, Hours, Days, Months, Years);
  /// <summary>Was das Fenster bei einem Fehler anbietet.</summary>
  TAtlasIssueFix = (None, EnterToken, Settings, Browser, Retry);
{$SCOPEDENUMS OFF}

  TAtlasIssueBadge = record
    Kind: TAtlasIssueBadgeKind;
    Text: string;
    /// <summary>Created, Updated: Zeitpunkt (UTC).</summary>
    Time: TDateTime;
  end;

  TAtlasIssueAge = record
    UnitKind: TAtlasIssueAgeUnit;
    Count: Integer;
  end;

  TAtlasIssuePreview = class
  public const
    /// <summary>So viele neueste Kommentare sind offen; ältere eingeklappt.</summary>
    ShownComments = 3;
    /// <summary>Zeitgrenze des Ladens.</summary>
    TimeoutMs = 10000;
    /// <summary>Größte Bilddatei für die Vorschau.</summary>
    MaxImageBytes = 8 * 1024 * 1024;
    /// <summary>Größter Anhang zum Öffnen.</summary>
    MaxAttachmentBytes = 64 * 1024 * 1024;
    /// <summary>Spielraum zwischen dem Anker einer Meldung und der Zeit des Kommentars.</summary>
    AnchorSlackMs = 2000;
  public
    class function Badges(const ADetails: TAtlasTrackerDetails): TArray<TAtlasIssueBadge>; static;
    /// <summary>Abstand von AThen bis ANow (beide UTC).</summary>
    class function Age(AThen, ANow: TDateTime): TAtlasIssueAge; static;
    /// <summary>Anzahl eingeklappter älterer Kommentare (0, wenn AExpanded).</summary>
    class function CollapsedComments(ACount: Integer; AExpanded: Boolean): Integer; static;
    /// <summary>Kommentar zum Anker einer Meldung (#1271, UTC): der erste, der höchstens AnchorSlackMs vor AAnchor
    /// angelegt wurde (Aktivität und Kommentar tragen nicht immer dieselbe Millisekunde); ohne passenden der
    /// letzte. -1 ohne Kommentare oder ohne Anker.</summary>
    class function CommentAt(const AComments: TArray<TAtlasTrackerComment>; AAnchor: TDateTime): Integer; static;
    /// <summary>Adresse eines Bilds im Markdown: relative Namen über die Anhänge; '' ohne.</summary>
    class function ImageUrl(const ADetails: TAtlasTrackerDetails; const AUrl: string): string; static;
    /// <summary>Bild bzw. Anhang darf mit dem Transport des Trackers geladen werden: https beim Server
    /// AApiServer (dem einzigen, an den das Token geht).</summary>
    class function MayLoad(const AUrl, AApiServer: string): Boolean; static;
    /// <summary>Darf im Browser geöffnet werden: http(s) ohne Benutzer in der Adresse.</summary>
    class function MayBrowse(const AUrl: string): Boolean; static;
    class function FixOf(AError: TAtlasCiFetchError): TAtlasIssueFix; static;
    /// <summary>Kennung aus einer Eingabe ("ATL-12", "#753", "753", Adresse eines Issues); '' ungültig.
    /// </summary>
    class function KeyOf(const AProvider, AInput: string): string; static;
    /// <summary>Beispiel für die Eingabe: GitHub "#753", sonst "ATL-123".</summary>
    class function KeyExample(const AProvider: string): string; static;
    /// <summary>Dateiname für einen Anhang (ohne Pfadteile und verbotene Zeichen).</summary>
    class function SafeFileName(const AName: string): string; static;
  end;

implementation

uses
  System.DateUtils,
  System.StrUtils;

{ TAtlasIssueHistoryEntry }

class function TAtlasIssueHistoryEntry.Create(const ATarget: TAtlasTrackerTarget;
  const AKey: string): TAtlasIssueHistoryEntry;
begin
  Result.Target := ATarget;
  Result.Key := Trim(AKey);
end;

function TAtlasIssueHistoryEntry.SameAs(const AOther: TAtlasIssueHistoryEntry): Boolean;
begin
  Result := SameText(Target.Server, AOther.Target.Server) and SameText(Target.Project, AOther.Target.Project) and
    SameText(Key, AOther.Key);
end;

{ TAtlasIssueHistory }

constructor TAtlasIssueHistory.Create;
begin
  inherited Create;
  FEntries := nil;
  FIndex := -1;
end;

procedure TAtlasIssueHistory.Visit(const AEntry: TAtlasIssueHistoryEntry);
begin
  if (FIndex >= 0) and FEntries[FIndex].SameAs(AEntry) then
    Exit;
  SetLength(FEntries, FIndex + 1);
  FEntries := FEntries + [AEntry];
  if Length(FEntries) > MaxEntries then
    FEntries := Copy(FEntries, Length(FEntries) - MaxEntries, MaxEntries);
  FIndex := High(FEntries);
end;

function TAtlasIssueHistory.CanBack: Boolean;
begin
  Result := FIndex > 0;
end;

function TAtlasIssueHistory.CanForward: Boolean;
begin
  Result := (FIndex >= 0) and (FIndex < High(FEntries));
end;

function TAtlasIssueHistory.GoBack(out AEntry: TAtlasIssueHistoryEntry): Boolean;
begin
  Result := CanBack;
  if Result then
    Dec(FIndex);
  Current(AEntry);
end;

function TAtlasIssueHistory.GoForward(out AEntry: TAtlasIssueHistoryEntry): Boolean;
begin
  Result := CanForward;
  if Result then
    Inc(FIndex);
  Current(AEntry);
end;

function TAtlasIssueHistory.Current(out AEntry: TAtlasIssueHistoryEntry): Boolean;
begin
  AEntry := Default(TAtlasIssueHistoryEntry);
  Result := FIndex >= 0;
  if Result then
    AEntry := FEntries[FIndex];
end;

function TAtlasIssueHistory.Count: Integer;
begin
  Result := Length(FEntries);
end;

procedure TAtlasIssueHistory.Clear;
begin
  FEntries := nil;
  FIndex := -1;
end;

{ TAtlasIssuePreview }

class function TAtlasIssuePreview.Badges(const ADetails: TAtlasTrackerDetails): TArray<TAtlasIssueBadge>;

  procedure Add(AKind: TAtlasIssueBadgeKind; const AText: string; ATime: TDateTime);
  var
    mBadge: TAtlasIssueBadge;
  begin
    if (AText = '') and (ATime <= 0) then
      Exit;
    mBadge.Kind := AKind;
    mBadge.Text := AText;
    mBadge.Time := ATime;
    Result := Result + [mBadge];
  end;

var
  mLabel: string;
begin
  Result := nil;
  Add(TAtlasIssueBadgeKind.State, ADetails.State, 0);
  Add(TAtlasIssueBadgeKind.Priority, ADetails.Priority, 0);
  Add(TAtlasIssueBadgeKind.Kind, ADetails.Kind, 0);
  Add(TAtlasIssueBadgeKind.Assignee, ADetails.Assignee, 0);
  Add(TAtlasIssueBadgeKind.Sprint, ADetails.Sprint, 0);
  for mLabel in ADetails.Labels do
    Add(TAtlasIssueBadgeKind.LabelName, mLabel, 0);
  Add(TAtlasIssueBadgeKind.Created, '', ADetails.Created);
  Add(TAtlasIssueBadgeKind.Updated, '', ADetails.Updated);
end;

class function TAtlasIssuePreview.Age(AThen, ANow: TDateTime): TAtlasIssueAge;
var
  mMinutes: Int64;
begin
  Result := Default(TAtlasIssueAge);
  mMinutes := MinutesBetween(ANow, AThen);
  if (AThen <= 0) or (AThen > ANow) or (mMinutes < 1) then
    Result.UnitKind := TAtlasIssueAgeUnit.JustNow
  else if mMinutes < 60 then
  begin
    Result.UnitKind := TAtlasIssueAgeUnit.Minutes;
    Result.Count := Integer(mMinutes);
  end
  else if mMinutes < 24 * 60 then
  begin
    Result.UnitKind := TAtlasIssueAgeUnit.Hours;
    Result.Count := Integer(mMinutes div 60);
  end
  else if mMinutes < 31 * 24 * 60 then
  begin
    Result.UnitKind := TAtlasIssueAgeUnit.Days;
    Result.Count := Integer(mMinutes div (24 * 60));
  end
  else if mMinutes < 365 * 24 * 60 then
  begin
    Result.UnitKind := TAtlasIssueAgeUnit.Months;
    Result.Count := Integer(mMinutes div (30 * 24 * 60));
  end
  else
  begin
    Result.UnitKind := TAtlasIssueAgeUnit.Years;
    Result.Count := Integer(mMinutes div (365 * 24 * 60));
  end;
end;

class function TAtlasIssuePreview.CollapsedComments(ACount: Integer; AExpanded: Boolean): Integer;
begin
  Result := 0;
  if not AExpanded and (ACount > ShownComments) then
    Result := ACount - ShownComments;
end;

class function TAtlasIssuePreview.CommentAt(const AComments: TArray<TAtlasTrackerComment>;
  AAnchor: TDateTime): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  if (AAnchor <= 0) or (Length(AComments) = 0) then
    Exit;
  for mIndex := 0 to High(AComments) do
    if AComments[mIndex].Created >= AAnchor - AnchorSlackMs / MSecsPerDay then
      Exit(mIndex);
  Result := High(AComments);
end;

class function TAtlasIssuePreview.ImageUrl(const ADetails: TAtlasTrackerDetails; const AUrl: string): string;
var
  mUrl: string;
  mIndex: Integer;
begin
  mUrl := Trim(AUrl);
  if StartsText('https://', mUrl) or StartsText('http://', mUrl) then
    Exit(mUrl);
  // YouTrack: ![](bildschirm.png) nennt einen Anhang.
  mIndex := ADetails.AttachmentIndex(mUrl);
  Result := '';
  if mIndex >= 0 then
    Result := ADetails.Attachments[mIndex].Url;
end;

class function TAtlasIssuePreview.MayLoad(const AUrl, AApiServer: string): Boolean;
var
  mServer: string;
begin
  mServer := TAtlasTrackerTarget.Create('', AUrl, '', '').Server;
  Result := StartsText('https://', mServer) and (AApiServer <> '') and SameText(mServer, AApiServer);
end;

class function TAtlasIssuePreview.MayBrowse(const AUrl: string): Boolean;
begin
  Result := (StartsText('https://', AUrl) or StartsText('http://', AUrl)) and
    (TAtlasTrackerTarget.Create('', AUrl, '', '').Server <> '');
end;

class function TAtlasIssuePreview.FixOf(AError: TAtlasCiFetchError): TAtlasIssueFix;
begin
  case AError of
    TAtlasCiFetchError.Unauthorized:
      Result := TAtlasIssueFix.EnterToken;
    TAtlasCiFetchError.NotConfigured, TAtlasCiFetchError.UnknownProvider:
      Result := TAtlasIssueFix.Settings;
    TAtlasCiFetchError.NotFound:
      Result := TAtlasIssueFix.Browser;
    TAtlasCiFetchError.Network, TAtlasCiFetchError.Timeout, TAtlasCiFetchError.Server, TAtlasCiFetchError.Invalid:
      Result := TAtlasIssueFix.Retry;
  else
    Result := TAtlasIssueFix.None;
  end;
end;

class function TAtlasIssuePreview.KeyExample(const AProvider: string): string;
begin
  if SameText(AProvider, TAtlasTrackerTarget.GitHub) then
    Result := '#753'
  else
    Result := 'ATL-123';
end;

class function TAtlasIssuePreview.KeyOf(const AProvider, AInput: string): string;
var
  mText: string;
  mIndex: Integer;
begin
  Result := '';
  mText := Trim(AInput);
  // Adresse eines Issues: letzter Pfadteil (".../issue/ATL-12", ".../issues/753").
  if StartsText('https://', mText) or StartsText('http://', mText) then
  begin
    while EndsStr('/', mText) do
      Delete(mText, Length(mText), 1);
    mText := Copy(mText, LastDelimiter('/', mText) + 1, MaxInt);
    if Pos('?', mText) > 0 then
      mText := Copy(mText, 1, Pos('?', mText) - 1);
    if Pos('#', mText) > 0 then
      mText := Copy(mText, 1, Pos('#', mText) - 1);
  end;
  if SameText(AProvider, TAtlasTrackerTarget.GitHub) then
  begin
    if StartsStr('#', mText) then
      Delete(mText, 1, 1);
    for mIndex := 1 to Length(mText) do
      if not CharInSet(mText[mIndex], ['0'..'9']) then
        Exit;
    if (mText <> '') and (StrToIntDef(mText, 0) > 0) then
      Result := '#' + IntToStr(StrToIntDef(mText, 0));
    Exit;
  end;
  // YouTrack: PROJ-123.
  if (mText = '') or (Pos('-', mText) < 2) or (Pos('-', mText) = Length(mText)) then
    Exit;
  for mIndex := 1 to Length(mText) do
    if not CharInSet(mText[mIndex], ['A'..'Z', 'a'..'z', '0'..'9', '-', '_']) then
      Exit;
  Result := UpperCase(mText);
end;

class function TAtlasIssuePreview.SafeFileName(const AName: string): string;
var
  mIndex: Integer;
begin
  // Letzter Teil nach / bzw. \, unabhängig vom Trennzeichen des Systems.
  Result := Trim(AName);
  Result := Copy(Result, LastDelimiter('/\', Result) + 1, MaxInt);
  for mIndex := 1 to Length(Result) do
    if CharInSet(Result[mIndex], ['<', '>', ':', '"', '|', '?', '*']) or (Result[mIndex] < ' ') then
      Result[mIndex] := '_';
  while (Result <> '') and CharInSet(Result[Length(Result)], ['.', ' ']) do
    Delete(Result, Length(Result), 1);
  while (Result <> '') and (Result[1] = '.') do
    Delete(Result, 1, 1);
  if Result = '' then
    Result := 'anhang';
  Result := Copy(Result, 1, 120);
end;

end.
