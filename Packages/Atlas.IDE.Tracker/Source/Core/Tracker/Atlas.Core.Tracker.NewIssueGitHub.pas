unit Atlas.Core.Tracker.NewIssueGitHub;

// GitHub-Teil von „Issue anlegen …“ (#2137), ohne VCL und Open Tools API:
// - Issue-Vorlagen: aus der Arbeitskopie (LocalFiles sucht den Ordner
//   .github/ISSUE_TEMPLATE nach oben bis zur Wurzel des Repositorys), sonst GET …/contents/.github/ISSUE_TEMPLATE und
//   je Datei …/contents/<pfad> (base64).
// - Meilensteine (GET …/milestones?state=open), Issue-Typen (GET
//   …/repos/<o>/<r>/issue-types, sonst …/orgs/<owner>/issue-types) und
//   Issue-Felder (…/issue-fields ebenso; Text, Zahl, Datum, Einfachauswahl).
//   Fehlt etwas, bleibt die Liste leer und der Dialog blendet die Zeile aus.
// - Beim Anlegen: Labels und Zuständige der Vorlage, milestone (Nummer), type
//   (Name) und issue_field_values im selben POST …/issues. GitHub übernimmt
//   Typ und Meilenstein nur mit Push-Rechten und schweigt sonst; Dropped liest
//   die Antwort und nennt, was fehlt. Projekte der Vorlage nimmt Atlas danach
//   über GraphQL auf (Internals.GitHubProjects).

interface

uses
  System.SysUtils,
  System.JSON,
  System.Diagnostics,
  Atlas.Core.Ci.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Contract.Files,
  Atlas.Core.Tracker.IssueForms;

type
{$SCOPEDENUMS ON}
  /// <summary>Art eines Issue-Felds; die Felder anderer Arten zeigt der Dialog nicht.</summary>
  TAtlasIssueFieldKind = (Text, Number, Date, SingleSelect);
{$SCOPEDENUMS OFF}

  TAtlasGitHubMilestone = record
    Number: Integer;
    Title: string;
    class function Create(ANumber: Integer; const ATitle: string): TAtlasGitHubMilestone; static;
  end;

  /// <summary>Ein Issue-Feld des Repositorys bzw. der Organisation.</summary>
  TAtlasGitHubIssueField = record
    Id: Int64;
    Name: string;
    Kind: TAtlasIssueFieldKind;
    /// <summary>Optionen (SingleSelect).</summary>
    Options: TArray<string>;
  end;

  /// <summary>Wert eines Issue-Felds für das Anlegen.</summary>
  TAtlasGitHubFieldValue = record
    FieldId: Int64;
    Kind: TAtlasIssueFieldKind;
    Value: string;
    class function Create(const AField: TAtlasGitHubIssueField; const AValue: string): TAtlasGitHubFieldValue;
      static;
  end;

  /// <summary>Was der Dialog für GitHub zusätzlich anbietet; leer bei YouTrack.</summary>
  TAtlasGitHubIssueMeta = record
    Forms: TArray<TAtlasIssueForm>;
    /// <summary>„Leeres Issue“ erlaubt (config.yml).</summary>
    BlankAllowed: Boolean;
    Milestones: TArray<TAtlasGitHubMilestone>;
    IssueTypes: TArray<string>;
    Fields: TArray<TAtlasGitHubIssueField>;
    class function Empty: TAtlasGitHubIssueMeta; static;
  end;

  /// <summary>GitHub-Angaben eines Entwurfs über Titel, Beschreibung und Labels hinaus.</summary>
  TAtlasGitHubDraft = record
    /// <summary>Labels und Zuständige der Vorlage (kommen zu denen des Dialogs).</summary>
    Labels: TArray<string>;
    Assignees: TArray<string>;
    /// <summary>Nummer des Meilensteins; 0 = keiner.</summary>
    Milestone: Integer;
    /// <summary>Issue-Typ; '' = keiner.</summary>
    IssueType: string;
    /// <summary>Projekte „owner/nummer“ der Vorlage.</summary>
    Projects: TArray<string>;
    FieldValues: TArray<TAtlasGitHubFieldValue>;
    class function Empty: TAtlasGitHubDraft; static;
  end;

  /// <summary>Was GitHub beim Anlegen nicht übernommen hat.</summary>
  TAtlasGitHubDropped = record
    Milestone: Boolean;
    IssueType: Boolean;
    /// <summary>Projekte, in die das Issue nicht kam.</summary>
    Projects: TArray<string>;
    function Any: Boolean;
    class function Empty: TAtlasGitHubDropped; static;
  end;

  /// <summary>Einstellungen für das Laden.</summary>
  TAtlasGitHubMetaRequest = record
    /// <summary>issues.create.templates.</summary>
    Templates: Boolean;
    /// <summary>Dateien aus .github/ISSUE_TEMPLATE der Arbeitskopie; leer = aus dem Repository laden.</summary>
    LocalFiles: TArray<TAtlasIssueFormFile>;
    class function Create(ATemplates: Boolean; const ALocalFiles: TArray<TAtlasIssueFormFile>):
      TAtlasGitHubMetaRequest; static;
  end;

  TAtlasGitHubNewIssue = class
  public const
    /// <summary>Höchstens so viele Vorlagen werden aus dem Repository geladen.</summary>
    cMaxFiles = 20;
    /// <summary>Höchstens so viele Ordner sucht LocalFiles nach oben.</summary>
    cMaxDepth = 32;
  public
    /// <summary>Vorlagen der Arbeitskopie: von AStart nach oben bis zum ersten Ordner mit .github/ISSUE_TEMPLATE;
    /// die Suche endet an der Wurzel des Repositorys (.git). Leer ohne Vorlagen.</summary>
    class function LocalFiles(const AFiles: IAtlasTrackerFiles; const AStart: string): TArray<TAtlasIssueFormFile>;
      static;
    /// <summary>Seite des Repositorys im Browser ("https://github.com/owner/repo"); '' ohne Server oder Projekt.
    /// </summary>
    class function RepositoryPage(const ATarget: TAtlasTrackerTarget): string; static;
    /// <summary>…/repos/&lt;owner/repo&gt;/contents/&lt;APath&gt;; '' ohne Server oder Projekt.</summary>
    class function ContentsUrl(const ATarget: TAtlasTrackerTarget; const APath: string): string; static;
    /// <summary>Namen der Dateien einer Ordnerliste von …/contents.</summary>
    class function ParseListing(const AText: string): TArray<string>; static;
    /// <summary>Inhalt einer Datei von …/contents (base64, UTF-8); False ohne.</summary>
    class function ParseContent(const AText: string; out AContent: string): Boolean; static;
    class function MilestonesUrl(const ATarget: TAtlasTrackerTarget): string; static;
    /// <summary>Offene Meilensteine (number, title); False bei ungültigem JSON.</summary>
    class function ParseMilestones(const AText: string; out AMilestones: TArray<TAtlasGitHubMilestone>): Boolean;
      static;
    /// <summary>Adressen der Issue-Typen: Repository, dann Organisation.</summary>
    class function IssueTypesUrls(const ATarget: TAtlasTrackerTarget): TArray<string>; static;
    /// <summary>Namen der Typen (ohne abgeschaltete); False bei ungültigem JSON.</summary>
    class function ParseIssueTypes(const AText: string; out ATypes: TArray<string>): Boolean; static;
    /// <summary>Adressen der Issue-Felder: Repository, dann Organisation.</summary>
    class function IssueFieldsUrls(const ATarget: TAtlasTrackerTarget): TArray<string>; static;
    /// <summary>Felder der Arten Text, Zahl, Datum und Einfachauswahl; False bei ungültigem JSON.</summary>
    class function ParseIssueFields(const AText: string; out AFields: TArray<TAtlasGitHubIssueField>): Boolean;
      static;
    /// <summary>AValue passt zur Art von AField: Zahl, Datum JJJJ-MM-TT, Option der Auswahl; leer passt immer.
    /// </summary>
    class function ValidValue(const AField: TAtlasGitHubIssueField; const AValue: string): Boolean; static;
    /// <summary>Labels, Zuständige, milestone, type und issue_field_values in ARoot (Inhalt von POST …/issues).
    /// </summary>
    class procedure AddTo(ARoot: TJSONObject; const ADraft: TAtlasGitHubDraft); static;
    /// <summary>Was die Antwort auf das Anlegen von ADraft nicht trägt (Meilenstein, Typ).</summary>
    class function Dropped(const AText: string; const ADraft: TAtlasGitHubDraft): TAtlasGitHubDropped; static;
    /// <summary>"node_id" der Antwort; '' ohne.</summary>
    class function NodeId(const AText: string): string; static;
    /// <summary>Vorlagen, Meilensteine, Typen und Felder laden; was nicht gelesen werden kann, bleibt leer.
    /// </summary>
    class function Load(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
      const ARequest: TAtlasGitHubMetaRequest; const AWatch: TStopwatch; ATimeoutMs: Integer): TAtlasGitHubIssueMeta;
      static;
    /// <summary>Issue (ANodeId) in die Projekte AProjects aufnehmen; Ergebnis: Projekte, bei denen es scheiterte.
    /// </summary>
    class function AddToProjects(const ACall: TAtlasTrackerCall; const AWatch: TStopwatch;
      const ASend: IAtlasCiSend; const ANodeId: string; const AProjects: TArray<string>): TArray<string>; static;
  end;

implementation

uses
  System.StrUtils,
  System.DateUtils,
  Atlas.Text.Json,
  Atlas.Text.Uris,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Internals.GitHubApi,
  Atlas.Core.Tracker.Internals.GitHubProjects;

const
  cKindNames: array[TAtlasIssueFieldKind] of string = ('text', 'number', 'date', 'single_select');
  cBase64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  /// <summary>Vier Base64-Zeichen tragen drei Bytes; jedes Zeichen sechs Bit.</summary>
  cBase64Chars = 4;
  cBase64Bytes = 3;
  cBitsPerChar = 6;
  cBitsPerByte = 8;
  /// <summary>Puffer der noch nicht ausgegebenen Bits (drei Bytes).</summary>
  cBitWindow = $FFFFFF;
  /// <summary>HTTP-Antwort „OK“.</summary>
  cHttpOk = 200;

{ TAtlasGitHubMilestone }

class function TAtlasGitHubMilestone.Create(ANumber: Integer; const ATitle: string): TAtlasGitHubMilestone;
begin
  Result.Number := ANumber;
  Result.Title := ATitle;
end;

{ TAtlasGitHubFieldValue }

class function TAtlasGitHubFieldValue.Create(const AField: TAtlasGitHubIssueField;
  const AValue: string): TAtlasGitHubFieldValue;
begin
  Result.FieldId := AField.Id;
  Result.Kind := AField.Kind;
  Result.Value := AValue;
end;

{ TAtlasGitHubIssueMeta }

class function TAtlasGitHubIssueMeta.Empty: TAtlasGitHubIssueMeta;
begin
  Result := Default(TAtlasGitHubIssueMeta);
  Result.Forms := nil;
  Result.BlankAllowed := True;
  Result.Milestones := nil;
  Result.IssueTypes := nil;
  Result.Fields := nil;
end;

{ TAtlasGitHubDraft }

class function TAtlasGitHubDraft.Empty: TAtlasGitHubDraft;
begin
  Result := Default(TAtlasGitHubDraft);
  Result.Labels := nil;
  Result.Assignees := nil;
  Result.Projects := nil;
  Result.FieldValues := nil;
end;

{ TAtlasGitHubDropped }

function TAtlasGitHubDropped.Any: Boolean;
begin
  Result := Milestone or IssueType or (Length(Projects) > 0);
end;

class function TAtlasGitHubDropped.Empty: TAtlasGitHubDropped;
begin
  Result := Default(TAtlasGitHubDropped);
  Result.Projects := nil;
end;

{ TAtlasGitHubMetaRequest }

class function TAtlasGitHubMetaRequest.Create(ATemplates: Boolean;
  const ALocalFiles: TArray<TAtlasIssueFormFile>): TAtlasGitHubMetaRequest;
begin
  Result.Templates := ATemplates;
  Result.LocalFiles := ALocalFiles;
end;

{ Adressen }

function RepoBase(const ATarget: TAtlasTrackerTarget): string;
begin
  Result := '';
  if ATarget.Configured and (TAtlasGitHubApi.Base(ATarget) <> '') and (Pos('/', ATarget.Project) > 1) then
  begin
    Result := TAtlasGitHubApi.Base(ATarget) + '/repos/' + ATarget.Project;
  end;
end;

/// <summary>…/orgs/&lt;owner&gt;; '' ohne Server oder Projekt.</summary>
function OrgBase(const ATarget: TAtlasTrackerTarget): string;
begin
  Result := '';
  if RepoBase(ATarget) <> '' then
  begin
    Result := TAtlasGitHubApi.Base(ATarget) + '/orgs/' + Copy(ATarget.Project, 1, Pos('/', ATarget.Project) - 1);
  end;
end;

class function TAtlasGitHubNewIssue.RepositoryPage(const ATarget: TAtlasTrackerTarget): string;
begin
  Result := '';
  if (ATarget.Server <> '') and (Pos('/', ATarget.Project) > 1) then
  begin
    Result := ATarget.Server + '/' + TTextUris.PercentEncode(ATarget.Project);
  end;
end;

class function TAtlasGitHubNewIssue.ContentsUrl(const ATarget: TAtlasTrackerTarget; const APath: string): string;
begin
  Result := RepoBase(ATarget);
  if Result <> '' then
  begin
    Result := Result + '/contents/' + TTextUris.PercentEncode(APath);
  end;
end;

class function TAtlasGitHubNewIssue.MilestonesUrl(const ATarget: TAtlasTrackerTarget): string;
begin
  Result := RepoBase(ATarget);
  if Result <> '' then
  begin
    Result := Result + '/milestones?state=open&sort=due_on&per_page=100';
  end;
end;

class function TAtlasGitHubNewIssue.IssueTypesUrls(const ATarget: TAtlasTrackerTarget): TArray<string>;
begin
  Result := nil;
  if RepoBase(ATarget) <> '' then
  begin
    Result := [RepoBase(ATarget) + '/issue-types', OrgBase(ATarget) + '/issue-types'];
  end;
end;

class function TAtlasGitHubNewIssue.IssueFieldsUrls(const ATarget: TAtlasTrackerTarget): TArray<string>;
begin
  Result := nil;
  if RepoBase(ATarget) <> '' then
  begin
    Result := [RepoBase(ATarget) + '/issue-fields', OrgBase(ATarget) + '/issue-fields'];
  end;
end;

{ Lesen }

/// <summary>Liste der Objekte in AText; nil bei ungültigem JSON bzw. ohne Liste. Der Aufrufer gibt ARoot frei.
/// </summary>
function ListOf(const AText: string; out ARoot: TJSONValue): TJSONArray;
begin
  ARoot := TJSONObject.ParseJSONValue(AText);
  Result := nil;
  if ARoot is TJSONArray then
  begin
    Result := TJSONArray(ARoot);
  end;
end;

class function TAtlasGitHubNewIssue.ParseListing(const AText: string): TArray<string>;
var
  mRoot, mItem: TJSONValue;
  mList: TJSONArray;
begin
  Result := nil;
  mList := ListOf(AText, mRoot);
  try
    if mList = nil then
    begin
      Exit;
    end;
    for mItem in mList do
    begin
      if (mItem is TJSONObject) and SameText(TJsonRead.Text(TJSONObject(mItem), 'type'), 'file') and
        (TJsonRead.Text(TJSONObject(mItem), 'name') <> '') then
      begin
        Result := Result + [TJsonRead.Text(TJSONObject(mItem), 'name')];
      end;
    end;
  finally
    mRoot.Free;
  end;
end;

/// <summary>Base64 ohne Zeilenumbrüche und Füllzeichen zu Bytes; False bei fremden Zeichen.</summary>
function DecodeBase64(const AText: string; out ABytes: TBytes): Boolean;
var
  mChar: Char;
  mValue, mBits, mDigit, mCount: Integer;
begin
  SetLength(ABytes, Length(AText) * cBase64Bytes div cBase64Chars + cBase64Bytes);
  mValue := 0;
  mBits := 0;
  mCount := 0;
  for mChar in AText do
  begin
    if CharInSet(mChar, [#10, #13, ' ', '=']) then
    begin
      Continue;
    end;
    mDigit := Pos(mChar, cBase64) - 1;
    if mDigit < 0 then
    begin
      Exit(False);
    end;
    mValue := ((mValue shl cBitsPerChar) or mDigit) and cBitWindow;
    Inc(mBits, cBitsPerChar);
    if mBits >= cBitsPerByte then
    begin
      Dec(mBits, cBitsPerByte);
      ABytes[mCount] := Byte((mValue shr mBits) and $FF);
      Inc(mCount);
    end;
  end;
  SetLength(ABytes, mCount);
  Result := True;
end;

class function TAtlasGitHubNewIssue.ParseContent(const AText: string; out AContent: string): Boolean;
var
  mRoot: TJSONValue;
  mBytes: TBytes;
begin
  AContent := '';
  Result := False;
  mRoot := TJSONObject.ParseJSONValue(AText);
  try
    if not (mRoot is TJSONObject) or not SameText(TJsonRead.Text(TJSONObject(mRoot), 'encoding'), 'base64') or
      not DecodeBase64(TJsonRead.Text(TJSONObject(mRoot), 'content'), mBytes) then
    begin
      Exit;
    end;
    AContent := TEncoding.UTF8.GetString(mBytes);
    Result := True;
  finally
    mRoot.Free;
  end;
end;

class function TAtlasGitHubNewIssue.ParseMilestones(const AText: string;
  out AMilestones: TArray<TAtlasGitHubMilestone>): Boolean;
var
  mRoot, mItem: TJSONValue;
  mList: TJSONArray;
  mNumber: Integer;
begin
  AMilestones := nil;
  mList := ListOf(AText, mRoot);
  try
    Result := mList <> nil;
    if not Result then
    begin
      Exit;
    end;
    for mItem in mList do
    begin
      if not (mItem is TJSONObject) then
      begin
        Continue;
      end;
      mNumber := TJsonRead.Int(TJSONObject(mItem), 'number');
      if (mNumber > 0) and (TJsonRead.Text(TJSONObject(mItem), 'title') <> '') then
      begin
        AMilestones := AMilestones + [TAtlasGitHubMilestone.Create(mNumber,
          TJsonRead.Text(TJSONObject(mItem), 'title'))];
      end;
    end;
  finally
    mRoot.Free;
  end;
end;

class function TAtlasGitHubNewIssue.ParseIssueTypes(const AText: string; out ATypes: TArray<string>): Boolean;
var
  mRoot, mItem: TJSONValue;
  mList: TJSONArray;
begin
  ATypes := nil;
  mList := ListOf(AText, mRoot);
  try
    Result := mList <> nil;
    if not Result then
    begin
      Exit;
    end;
    for mItem in mList do
    begin
      if (mItem is TJSONObject) and TJsonRead.FlagOr(TJSONObject(mItem), 'is_enabled', True) and
        (TJsonRead.Text(TJSONObject(mItem), 'name') <> '') then
      begin
        ATypes := ATypes + [TJsonRead.Text(TJSONObject(mItem), 'name')];
      end;
    end;
  finally
    mRoot.Free;
  end;
end;

function FieldKindOf(const AName: string; out AKind: TAtlasIssueFieldKind): Boolean;
var
  mKind: TAtlasIssueFieldKind;
begin
  for mKind := Low(TAtlasIssueFieldKind) to High(TAtlasIssueFieldKind) do
  begin
    if SameText(AName, cKindNames[mKind]) then
    begin
      AKind := mKind;
      Exit(True);
    end;
  end;
  AKind := TAtlasIssueFieldKind.Text;
  Result := False;
end;

/// <summary>Ein Feld aus AItem; False bei unbekannter Art oder ohne Kennung.</summary>
function ReadIssueField(AItem: TJSONObject; out AField: TAtlasGitHubIssueField): Boolean;
var
  mOptions: TJSONArray;
  mOption: TJSONValue;
begin
  AField := Default(TAtlasGitHubIssueField);
  AField.Options := nil;
  AField.Name := TJsonRead.Text(AItem, 'name');
  Result := TJsonRead.TryInt64(AItem, 'id', AField.Id) and (AField.Name <> '') and
    FieldKindOf(TJsonRead.Text(AItem, 'data_type'), AField.Kind);
  if not Result then
  begin
    Exit;
  end;
  mOptions := TJsonRead.Items(AItem, 'options');
  if mOptions = nil then
  begin
    Exit;
  end;
  for mOption in mOptions do
  begin
    if (mOption is TJSONObject) and (TJsonRead.Text(TJSONObject(mOption), 'name') <> '') then
    begin
      AField.Options := AField.Options + [TJsonRead.Text(TJSONObject(mOption), 'name')];
    end;
  end;
end;

class function TAtlasGitHubNewIssue.ParseIssueFields(const AText: string;
  out AFields: TArray<TAtlasGitHubIssueField>): Boolean;
var
  mRoot, mItem: TJSONValue;
  mList: TJSONArray;
  mField: TAtlasGitHubIssueField;
begin
  AFields := nil;
  mList := ListOf(AText, mRoot);
  try
    Result := mList <> nil;
    if not Result then
    begin
      Exit;
    end;
    for mItem in mList do
    begin
      if (mItem is TJSONObject) and ReadIssueField(TJSONObject(mItem), mField) then
      begin
        AFields := AFields + [mField];
      end;
    end;
  finally
    mRoot.Free;
  end;
end;

class function TAtlasGitHubNewIssue.ValidValue(const AField: TAtlasGitHubIssueField; const AValue: string): Boolean;
var
  mNumber: Double;
  mDate: TDateTime;
begin
  if Trim(AValue) = '' then
  begin
    Exit(True);
  end;
  case AField.Kind of
    TAtlasIssueFieldKind.Number:
      Result := TryStrToFloat(Trim(AValue), mNumber, TFormatSettings.Invariant);
    TAtlasIssueFieldKind.Date:
      Result := (Length(Trim(AValue)) = 10) and TryISO8601ToDate(Trim(AValue), mDate, False);
    TAtlasIssueFieldKind.SingleSelect:
      Result := IndexText(Trim(AValue), AField.Options) >= 0;
  else
    Result := True;
  end;
end;

{ Anlegen }

/// <summary>Liste AName in ARoot um AValues ergänzen (ohne doppelte, ohne Groß-/Kleinschreibung).</summary>
procedure AddTexts(ARoot: TJSONObject; const AName: string; const AValues: TArray<string>);
var
  mList: TJSONArray;
  mItem: TJSONValue;
  mValue: string;
  mKnown: TArray<string>;
begin
  if Length(AValues) = 0 then
  begin
    Exit;
  end;
  mKnown := nil;
  mList := TJsonRead.Items(ARoot, AName);
  if mList = nil then
  begin
    mList := TJSONArray.Create;
    ARoot.AddPair(AName, mList);
  end;
  for mItem in mList do
  begin
    mKnown := mKnown + [mItem.Value];
  end;
  for mValue in AValues do
  begin
    if (Trim(mValue) <> '') and (IndexText(Trim(mValue), mKnown) < 0) then
    begin
      mList.Add(Trim(mValue));
      mKnown := mKnown + [Trim(mValue)];
    end;
  end;
end;

function FieldValuesJson(const AValues: TArray<TAtlasGitHubFieldValue>): TJSONArray;
var
  mValue: TAtlasGitHubFieldValue;
  mItem: TJSONObject;
  mNumber: Double;
begin
  Result := TJSONArray.Create;
  for mValue in AValues do
  begin
    if Trim(mValue.Value) = '' then
    begin
      Continue;
    end;
    mItem := TJSONObject.Create;
    mItem.AddPair('field_id', TJSONNumber.Create(mValue.FieldId));
    if (mValue.Kind = TAtlasIssueFieldKind.Number) and
      TryStrToFloat(Trim(mValue.Value), mNumber, TFormatSettings.Invariant) then
    begin
      mItem.AddPair('value', TJSONNumber.Create(mNumber));
    end
    else
    begin
      mItem.AddPair('value', Trim(mValue.Value));
    end;
    Result.AddElement(mItem);
  end;
end;

class procedure TAtlasGitHubNewIssue.AddTo(ARoot: TJSONObject; const ADraft: TAtlasGitHubDraft);
var
  mValues: TJSONArray;
begin
  AddTexts(ARoot, 'labels', ADraft.Labels);
  AddTexts(ARoot, 'assignees', ADraft.Assignees);
  if ADraft.Milestone > 0 then
  begin
    ARoot.AddPair('milestone', TJSONNumber.Create(ADraft.Milestone));
  end;
  if Trim(ADraft.IssueType) <> '' then
  begin
    ARoot.AddPair('type', Trim(ADraft.IssueType));
  end;
  mValues := FieldValuesJson(ADraft.FieldValues);
  if mValues.Count > 0 then
  begin
    ARoot.AddPair('issue_field_values', mValues);
  end
  else
  begin
    mValues.Free;
  end;
end;

class function TAtlasGitHubNewIssue.Dropped(const AText: string;
  const ADraft: TAtlasGitHubDraft): TAtlasGitHubDropped;
var
  mRoot: TJSONValue;
  mMilestone, mType: TJSONObject;
begin
  Result := TAtlasGitHubDropped.Empty;
  mRoot := TJSONObject.ParseJSONValue(AText);
  try
    if not (mRoot is TJSONObject) then
    begin
      Exit;
    end;
    mMilestone := TJsonRead.Obj(TJSONObject(mRoot), 'milestone');
    Result.Milestone := (ADraft.Milestone > 0) and ((mMilestone = nil) or
      (TJsonRead.Int(mMilestone, 'number') <> ADraft.Milestone));
    mType := TJsonRead.Obj(TJSONObject(mRoot), 'type');
    Result.IssueType := (Trim(ADraft.IssueType) <> '') and ((mType = nil) or
      not SameText(TJsonRead.Text(mType, 'name'), Trim(ADraft.IssueType)));
  finally
    mRoot.Free;
  end;
end;

class function TAtlasGitHubNewIssue.NodeId(const AText: string): string;
var
  mRoot: TJSONValue;
begin
  Result := '';
  mRoot := TJSONObject.ParseJSONValue(AText);
  try
    if mRoot is TJSONObject then
    begin
      Result := TJsonRead.Text(TJSONObject(mRoot), 'node_id');
    end;
  finally
    mRoot.Free;
  end;
end;

class function TAtlasGitHubNewIssue.AddToProjects(const ACall: TAtlasTrackerCall; const AWatch: TStopwatch;
  const ASend: IAtlasCiSend; const ANodeId: string; const AProjects: TArray<string>): TArray<string>;
var
  mProject: string;
begin
  Result := nil;
  for mProject in AProjects do
  begin
    if (ASend = nil) or not TAtlasGitHubProjects.AddIssue(ACall, AWatch, ASend, ANodeId, mProject) then
    begin
      Result := Result + [mProject];
    end;
  end;
end;

{ Laden }

/// <summary>GET mit Antwort 200 in der restlichen Zeit.</summary>
function Fetch(const ATransport: IAtlasCiTransport; const AUrl: string; const AWatch: TStopwatch;
  ATimeoutMs: Integer; out AText: string): Boolean;
var
  mStatus: Integer;
  mError: TAtlasCiFetchError;
begin
  AText := '';
  Result := (AUrl <> '') and (TAtlasGitHubApi.Remaining(AWatch, ATimeoutMs) > 1) and
    ATransport.Get(AUrl, TAtlasGitHubApi.Remaining(AWatch, ATimeoutMs), mStatus, AText, mError) and (mStatus = cHttpOk);
end;

/// <summary>Vorlagen aus dem Repository: Ordnerliste, dann jede Vorlage und config.yml.</summary>
function RemoteFiles(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const AWatch: TStopwatch; ATimeoutMs: Integer): TArray<TAtlasIssueFormFile>;
var
  mText, mContent, mName: string;
begin
  Result := nil;
  if not Fetch(ATransport, TAtlasGitHubNewIssue.ContentsUrl(ATarget, TAtlasIssueForms.cFolder), AWatch, ATimeoutMs,
    mText) then
  begin
    Exit;
  end;
  for mName in TAtlasGitHubNewIssue.ParseListing(mText) do
  begin
    if Length(Result) >= TAtlasGitHubNewIssue.cMaxFiles then
    begin
      Break;
    end;
    if (TAtlasIssueForms.IsFormFile(mName) or TAtlasIssueForms.IsConfigFile(mName)) and Fetch(ATransport,
      TAtlasGitHubNewIssue.ContentsUrl(ATarget, TAtlasIssueForms.cFolder + '/' + mName), AWatch, ATimeoutMs, mText) and
      TAtlasGitHubNewIssue.ParseContent(mText, mContent) then
    begin
      Result := Result + [TAtlasIssueFormFile.Create(mName, mContent)];
    end;
  end;
end;

function ReadTemplates(const AFiles: IAtlasTrackerFiles; const AFolder: string): TArray<TAtlasIssueFormFile>;
var
  mPath, mName, mText: string;
begin
  Result := nil;
  for mPath in AFiles.Files(AFolder, '*') do
  begin
    if Length(Result) >= TAtlasGitHubNewIssue.cMaxFiles then
    begin
      Break;
    end;
    mName := ExtractFileName(mPath);
    if (TAtlasIssueForms.IsFormFile(mName) or TAtlasIssueForms.IsConfigFile(mName)) and
      AFiles.ReadText(mPath, mText) then
    begin
      Result := Result + [TAtlasIssueFormFile.Create(mName, mText)];
    end;
  end;
end;

class function TAtlasGitHubNewIssue.LocalFiles(const AFiles: IAtlasTrackerFiles; const AStart: string):
  TArray<TAtlasIssueFormFile>;
var
  mFolder, mParent, mGit: string;
  mDepth: Integer;
begin
  Result := nil;
  mFolder := ExcludeTrailingPathDelimiter(AStart);
  mDepth := 0;
  while (mFolder <> '') and (mDepth < cMaxDepth) do
  begin
    Inc(mDepth);
    mParent := IncludeTrailingPathDelimiter(mFolder);
    if AFiles.FolderExists(mParent + '.github' + PathDelim + 'ISSUE_TEMPLATE') then
    begin
      Result := ReadTemplates(AFiles, mParent + '.github' + PathDelim + 'ISSUE_TEMPLATE');
      Exit;
    end;
    mGit := mParent + '.git';
    if AFiles.FolderExists(mGit) or AFiles.FileExists(mGit) then
    begin
      Exit;
    end;
    mParent := ExcludeTrailingPathDelimiter(ExtractFileDir(mFolder));
    if mParent = mFolder then
    begin
      Exit;
    end;
    mFolder := mParent;
  end;
end;

class function TAtlasGitHubNewIssue.Load(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const ARequest: TAtlasGitHubMetaRequest; const AWatch: TStopwatch; ATimeoutMs: Integer): TAtlasGitHubIssueMeta;
var
  mText, mUrl: string;
  mFiles: TArray<TAtlasIssueFormFile>;
begin
  Result := TAtlasGitHubIssueMeta.Empty;
  if (ATransport = nil) or (RepoBase(ATarget) = '') then
  begin
    Exit;
  end;
  if ARequest.Templates then
  begin
    mFiles := ARequest.LocalFiles;
    if Length(mFiles) = 0 then
    begin
      mFiles := RemoteFiles(ATarget, ATransport, AWatch, ATimeoutMs);
    end;
    Result.Forms := TAtlasIssueForms.ReadAll(mFiles, Result.BlankAllowed);
  end;
  if Fetch(ATransport, MilestonesUrl(ATarget), AWatch, ATimeoutMs, mText) then
  begin
    ParseMilestones(mText, Result.Milestones);
  end;
  for mUrl in IssueTypesUrls(ATarget) do
  begin
    if Fetch(ATransport, mUrl, AWatch, ATimeoutMs, mText) and ParseIssueTypes(mText, Result.IssueTypes) then
    begin
      Break;
    end;
  end;
  for mUrl in IssueFieldsUrls(ATarget) do
  begin
    if Fetch(ATransport, mUrl, AWatch, ATimeoutMs, mText) and ParseIssueFields(mText, Result.Fields) then
    begin
      Break;
    end;
  end;
end;

end.
