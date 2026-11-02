unit Atlas.Core.Tracker.CommentEditor;

// Kommentar-Editor für Issues (#1278), ohne VCL und Open Tools API. Gilt für
// alle Kommentarfelder von Atlas (Vorschau #1264, Beenden-Dialog #1266; die
// Beschreibung #1268 und die Rückfrage beim Ziehen #1272 nutzen dasselbe).
// - Auslöser an der Schreibmarke (TAtlasCommentEditing.Trigger): "@" mit
//   Buchstaben schlägt Benutzer vor, "#" mit Text oder Nummer bzw. bei
//   YouTrack das Projektkürzel mit "-" ("ATL-12", "ATL-Speicher") schlägt
//   Issues vor; die Anfrage baut TAtlasIssuePaletteSearch.Parse wie in der
//   Befehlspalette (#1270). Mitten im Wort, in E-Mail-Adressen ("a@b") und
//   Pfaden gibt es keinen Auslöser.
// - Ersetzen (Replace) setzt "@login" bzw. die Kennung an die Stelle des
//   getippten Worts; Markdown-Kürzel: Strg+B "**", Strg+I "_" (an und aus),
//   Strg+Umschalt+K Code-Block mit Sprache pascal.
// - Textbausteine (TAtlasCommentSnippets, issues.commentSnippets): Name und
//   Text, Platzhalter {branch}, {commit} (Kurz-Hash), {issue} und {version}
//   (Version des aktiven Projekts); ein unbekannter Wert lässt den Platzhalter
//   stehen, damit er beim Lesen auffällt.
// - Entwürfe (TAtlasCommentDrafts): Text je Tracker, Issue und Feld in
//   %LOCALAPPDATA%\Atlas\issues\drafts.json, über TAtlasDataFile gelesen und
//   atomar geschrieben, höchstens MaxDrafts (die ältesten fallen weg). Nie ein
//   Token, als Tracker nur Server und Projekt.
// - IAtlasCommentAssist: was die Oberfläche von der IDE braucht (Benutzer und
//   Issues im Hintergrund, Werte der Platzhalter, Textbausteine, Entwurf).

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Files.DataFile,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.PaletteSearch;

type
{$SCOPEDENUMS ON}
  /// <summary>None: kein Vorschlag; Mention: "@…"; Issue: "#…" bzw. "ATL-…".</summary>
  TAtlasCommentTriggerKind = (None, Mention, Issue);
{$SCOPEDENUMS OFF}

  /// <summary>Getipptes Wort, zu dem die Liste Vorschläge zeigt.</summary>
  TAtlasCommentTrigger = record
    Kind: TAtlasCommentTriggerKind;
    /// <summary>Zeichen vor dem Wort (wie SelStart eines Memos, ab 0), einschließlich "@" bzw. "#".</summary>
    Start: Integer;
    /// <summary>Länge des Worts bis zur Schreibmarke.</summary>
    Length: Integer;
    /// <summary>Mention: Text nach "@" ("an"); Issue: das Wort ("#42", "ATL-Speicher").</summary>
    Text: string;
    /// <summary>Issue: Anfrage wie in der Befehlspalette (Key, Text oder Recent).</summary>
    Query: TAtlasIssueSearchQuery;
    class function None: TAtlasCommentTrigger; static;
    /// <summary>Gleiche Art und gleicher Text (ohne Groß-/Kleinschreibung).</summary>
    function SameAs(const AOther: TAtlasCommentTrigger): Boolean;
  end;

  TAtlasCommentEditing = class
  public const
    /// <summary>Höchstens so viele Einträge in der Vorschlagsliste.</summary>
    MaxSuggestions = 8;
    /// <summary>Sprache des Code-Blocks (Strg+Umschalt+K).</summary>
    CodeLanguage = 'pascal';
    BoldMarker = '**';
    ItalicMarker = '_';
    /// <summary>Zeilenumbruch im Memo.</summary>
    LineBreak = #13#10;
  public
    /// <summary>Auslöser an der Schreibmarke ACaret (Zeichen davor, wie SelStart) für den Tracker ATarget.
    /// </summary>
    class function Trigger(const AText: string; ACaret: Integer; const ATarget: TAtlasTrackerTarget):
      TAtlasCommentTrigger; static;
    /// <summary>Wort von ATrigger durch AValue ersetzen; am Textende folgt ein Leerzeichen. ACaret: neue
    /// Schreibmarke.</summary>
    class function Replace(const AText: string; const ATrigger: TAtlasCommentTrigger; const AValue: string;
      out ACaret: Integer): string; static;
    /// <summary>Auswahl (ASelStart, ASelLength) durch AValue ersetzen; ACaret dahinter.</summary>
    class function Insert(const AText: string; ASelStart, ASelLength: Integer; const AValue: string;
      out ACaret: Integer): string; static;
    /// <summary>AMarker um die Auswahl setzen bzw. entfernen, wenn sie schon darin steht; ohne Auswahl ein leeres
    /// Paar mit der Schreibmarke dazwischen. AStart/ALength: neue Auswahl.</summary>
    class function ToggleInline(const AText: string; ASelStart, ASelLength: Integer; const AMarker: string;
      out AStart, ALength: Integer): string; static;
    /// <summary>Auswahl als Code-Block ("```pascal") auf eigenen Zeilen; ohne Auswahl ein leerer Block mit der
    /// Schreibmarke darin. AStart/ALength: der Code im Block.</summary>
    class function CodeBlock(const AText: string; ASelStart, ASelLength: Integer; out AStart, ALength: Integer):
      string; static;
    /// <summary>Was eine Erwähnung einfügt: "@login".</summary>
    class function MentionText(const AUser: TAtlasTrackerUser): string; static;
    /// <summary>Zeile der Liste: "@anna · Anna Berger" bzw. "@anna".</summary>
    class function UserRow(const AUser: TAtlasTrackerUser): string; static;
    /// <summary>Zeile der Liste: "ATL-12 · Titel · In Arbeit".</summary>
    class function IssueRow(const AIssue: TAtlasTrackerIssue): string; static;
  end;

  /// <summary>Werte der Platzhalter eines Textbausteins.</summary>
  TAtlasCommentValues = record
    /// <summary>Kennung des Issues ("ATL-123", "#753").</summary>
    Issue: string;
    Branch: string;
    /// <summary>Kurz-Hash bzw. "r42" (SVN).</summary>
    Commit: string;
    /// <summary>Version des aktiven Projekts ("1.2.0.0").</summary>
    Version: string;
    class function Create(const AIssue, ABranch, ACommit, AVersion: string): TAtlasCommentValues; static;
  end;

  TAtlasCommentSnippet = record
    Name: string;
    Text: string;
    class function Create(const AName, AText: string): TAtlasCommentSnippet; static;
  end;

  TAtlasCommentSnippets = class
  public const
    MaxSnippets = 50;
    MaxName = 80;
    MaxText = 4000;
  public
    /// <summary>Vorgaben von issues.commentSnippets.</summary>
    class function Defaults: TArray<TAtlasCommentSnippet>; static;
    /// <summary>Vorgaben als JSON wie im Schema.</summary>
    class function DefaultJson: string; static;
    /// <summary>Liste [{"name": …, "text": …}]; Einträge ohne Name oder Text entfallen, Längen werden gekürzt.
    /// False, wenn AJson keine Liste ist.</summary>
    class function Parse(const AJson: string; out ASnippets: TArray<TAtlasCommentSnippet>): Boolean; static;
    /// <summary>Wie Parse; ungültiges JSON ergibt die Vorgaben (eine leere Liste bleibt leer).</summary>
    class function Read(const AJson: string): TArray<TAtlasCommentSnippet>; static;
    class function ToJson(const ASnippets: TArray<TAtlasCommentSnippet>): string; static;
    /// <summary>Platzhalter ersetzen ({branch}, {commit}, {issue}, {version}, ohne Groß-/Kleinschreibung); ein
    /// leerer Wert lässt den Platzhalter stehen.</summary>
    class function Expand(const AText: string; const AValues: TAtlasCommentValues): string; static;
    /// <summary>AText enthält {branch} oder {commit} (braucht die Versionsverwaltung).</summary>
    class function NeedsVcs(const AText: string): Boolean; static;
  end;

  /// <summary>Entwürfe der Kommentarfelder (#1278).</summary>
  TAtlasCommentDrafts = class
  public const
    Version = 1;
    MaxDrafts = 100;
    /// <summary>Felder: Vorschau (#1264), Beenden-Dialog (#1266), Beschreibung (#1268), Rückfrage (#1272).</summary>
    FieldPreview = 'preview';
    FieldEnd = 'end';
    FieldDescription = 'description';
    FieldAsk = 'ask';
    FileName = 'drafts.json';
  private type
    TEntry = record
      Tracker: string;
      Issue: string;
      Field: string;
      Text: string;
      Saved: TDateTime;
    end;
  private
    FEntries: TList<TEntry>;
    FKept: string;
    FKind: string;
    function IndexOf(const ATracker, AIssue, AField: string): Integer;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Entwurf zu Tracker, Issue und Feld; False ohne.</summary>
    function Get(const ATracker, AIssue, AField: string; out AText: string; out ASaved: TDateTime): Boolean;
    /// <summary>Entwurf merken (zuerst, ein älterer desselben Felds entfällt); nur Leerraum = Delete.</summary>
    procedure Put(const ATracker, AIssue, AField, AText: string; ASaved: TDateTime);
    /// <summary>True, wenn es einen Entwurf gab.</summary>
    function Delete(const ATracker, AIssue, AField: string): Boolean;
    function Count: Integer;
    procedure Clear;
    function ToJson: string;
    /// <summary>Übernimmt AText; Einträge anderer Form fallen weg. False, wenn AText kein Objekt der Version ist.
    /// </summary>
    function Parse(const AText: string): Boolean;
    /// <summary>Wie TAtlasRecentIssues.LoadFromFile: fehlt oder unbrauchbar = leer; Kept = nicht überschreiben.
    /// </summary>
    function LoadFromFile(const AFileName: string): TAtlasDataLoad;
    /// <summary>Schreibt atomar; False, wenn LoadFromFile die vorhandene Datei nicht lesen konnte.</summary>
    function SaveToFile(const AFileName: string): Boolean;
    /// <summary>Schlüssel des Trackers: Server und Projekt (klein) wie bei den zuletzt geöffneten Issues.</summary>
    class function TrackerKey(const ATarget: TAtlasTrackerTarget): string; static;
    property Kind: string read FKind;
  end;

  TAtlasCommentUsersDone = reference to procedure(const AUsers: TArray<TAtlasTrackerUser>);
  TAtlasCommentIssuesDone = reference to procedure(const AIssues: TArray<TAtlasTrackerIssue>);
  TAtlasCommentValuesDone = reference to procedure(const AValues: TAtlasCommentValues);

  /// <summary>Was ein Kommentarfeld von der IDE bekommt (#1278); gebunden an Tracker, Issue und Feld. Antworten
  /// kommen im Hauptthread; eine neue Anfrage derselben Art ersetzt die alte (deren Antwort kommt nie).</summary>
  IAtlasCommentAssist = interface
    ['{CC119861-A5FF-4CBA-9293-2E26C48FEA40}']
    /// <summary>Tracker des Issues (für die Auslöser).</summary>
    function Target: TAtlasTrackerTarget;
    /// <summary>Textbausteine aus issues.commentSnippets.</summary>
    function Snippets: TArray<TAtlasCommentSnippet>;
    /// <summary>Benutzer zu AText (Hintergrund); ohne Tracker oder Token eine leere Liste.</summary>
    procedure FindUsers(const AText: string; const ADone: TAtlasCommentUsersDone);
    /// <summary>Issues zu AQuery (Hintergrund; Recent ohne Netz).</summary>
    procedure FindIssues(const AQuery: TAtlasIssueSearchQuery; const ADone: TAtlasCommentIssuesDone);
    /// <summary>Werte der Platzhalter (Versionsverwaltung im Hintergrund).</summary>
    procedure Values(const ADone: TAtlasCommentValuesDone);
    /// <summary>Offene Anfragen verwerfen.</summary>
    procedure Cancel;
    function LoadDraft(out AText: string; out ASaved: TDateTime): Boolean;
    /// <summary>Entwurf speichern; nur Leerraum löscht ihn.</summary>
    procedure SaveDraft(const AText: string);
    procedure DeleteDraft;
  end;

implementation

uses
  System.Character,
  System.DateUtils,
  System.JSON,
  System.Math,
  System.StrUtils;

const
  cMention = '@';
  cHash = '#';
  cFence = '```';

function IsNameChar(AChar: Char): Boolean;
begin
  Result := AChar.IsLetterOrDigit or CharInSet(AChar, ['_', '.', '-']);
end;

function IsBreak(AChar: Char): Boolean;
begin
  Result := CharInSet(AChar, [#13, #10]);
end;

{ TAtlasCommentTrigger }

class function TAtlasCommentTrigger.None: TAtlasCommentTrigger;
begin
  Result.Kind := TAtlasCommentTriggerKind.None;
  Result.Start := 0;
  Result.Length := 0;
  Result.Text := '';
  Result.Query := TAtlasIssueSearchQuery.None;
end;

function TAtlasCommentTrigger.SameAs(const AOther: TAtlasCommentTrigger): Boolean;
begin
  Result := (Kind = AOther.Kind) and SameText(Text, AOther.Text);
end;

{ TAtlasCommentEditing }

class function TAtlasCommentEditing.Trigger(const AText: string; ACaret: Integer;
  const ATarget: TAtlasTrackerTarget): TAtlasCommentTrigger;
var
  mStart: Integer;
  mWord: string;
  mMark: Char;
  mQuery: TAtlasIssueSearchQuery;
begin
  Result := TAtlasCommentTrigger.None;
  if (ACaret < 1) or (ACaret > System.Length(AText)) then
    Exit;
  // Mitten im Wort nicht: Die Schreibmarke steht am Ende des getippten Worts.
  if (ACaret < System.Length(AText)) and IsNameChar(AText[ACaret + 1]) then
    Exit;
  mStart := ACaret;
  while (mStart >= 1) and IsNameChar(AText[mStart]) do
    Dec(mStart);
  mWord := Copy(AText, mStart + 1, ACaret - mStart);
  if (mStart >= 1) and CharInSet(AText[mStart], [cMention, cHash]) then
  begin
    mMark := AText[mStart];
    // "a@b" (E-Mail), "##" und "`#" sind keine Auslöser.
    if (mStart > 1) and (IsNameChar(AText[mStart - 1]) or CharInSet(AText[mStart - 1], [cMention, cHash, '`', '/',
      '\'])) then
      Exit;
    if mWord = '' then
      Exit;
    if mMark = cMention then
    begin
      if not mWord[1].IsLetter then
        Exit;
      Result.Kind := TAtlasCommentTriggerKind.Mention;
      Result.Text := mWord;
    end
    else
    begin
      mQuery := TAtlasIssuePaletteSearch.Parse(ATarget, cHash + mWord);
      if mQuery.Kind = TAtlasIssueSearchKind.None then
        Exit;
      Result.Kind := TAtlasCommentTriggerKind.Issue;
      Result.Text := cHash + mWord;
      Result.Query := mQuery;
    end;
    Result.Start := mStart - 1;
    Result.Length := System.Length(mWord) + 1;
    Exit;
  end;
  // Projektkürzel mit "-" (YouTrack): ein eigenes Wort, nicht Teil eines Pfads oder Codes.
  if (mWord = '') or ((mStart >= 1) and CharInSet(AText[mStart], ['`', '/', '\'])) then
    Exit;
  mQuery := TAtlasIssuePaletteSearch.Parse(ATarget, mWord);
  if mQuery.Kind = TAtlasIssueSearchKind.None then
    Exit;
  Result.Kind := TAtlasCommentTriggerKind.Issue;
  Result.Text := mWord;
  Result.Query := mQuery;
  Result.Start := mStart;
  Result.Length := System.Length(mWord);
end;

class function TAtlasCommentEditing.Replace(const AText: string; const ATrigger: TAtlasCommentTrigger;
  const AValue: string; out ACaret: Integer): string;
begin
  Result := Copy(AText, 1, ATrigger.Start) + AValue + Copy(AText, ATrigger.Start + ATrigger.Length + 1, MaxInt);
  ACaret := ATrigger.Start + Length(AValue);
  // Am Ende weiterschreiben können; vor Leerzeichen oder Satzzeichen nichts ergänzen.
  if ACaret >= Length(Result) then
  begin
    Result := Result + ' ';
    Inc(ACaret);
  end
  else if Result[ACaret + 1] = ' ' then
    Inc(ACaret);
end;

class function TAtlasCommentEditing.Insert(const AText: string; ASelStart, ASelLength: Integer;
  const AValue: string; out ACaret: Integer): string;
var
  mStart, mLength: Integer;
begin
  mStart := EnsureRange(ASelStart, 0, Length(AText));
  mLength := EnsureRange(ASelLength, 0, Length(AText) - mStart);
  Result := Copy(AText, 1, mStart) + AValue + Copy(AText, mStart + mLength + 1, MaxInt);
  ACaret := mStart + Length(AValue);
end;

class function TAtlasCommentEditing.ToggleInline(const AText: string; ASelStart, ASelLength: Integer;
  const AMarker: string; out AStart, ALength: Integer): string;
var
  mStart, mLength, mSize: Integer;
  mBefore, mSelected, mAfter: string;
begin
  mStart := EnsureRange(ASelStart, 0, Length(AText));
  mLength := EnsureRange(ASelLength, 0, Length(AText) - mStart);
  mSize := Length(AMarker);
  mBefore := Copy(AText, 1, mStart);
  mSelected := Copy(AText, mStart + 1, mLength);
  mAfter := Copy(AText, mStart + mLength + 1, MaxInt);
  if mLength = 0 then
  begin
    Result := mBefore + AMarker + AMarker + mAfter;
    AStart := mStart + mSize;
    ALength := 0;
    Exit;
  end;
  // Schon ausgezeichnet: Zeichen um die Auswahl bzw. am Rand der Auswahl entfernen.
  if EndsStr(AMarker, mBefore) and StartsStr(AMarker, mAfter) then
  begin
    Result := Copy(mBefore, 1, Length(mBefore) - mSize) + mSelected + Copy(mAfter, mSize + 1, MaxInt);
    AStart := mStart - mSize;
    ALength := mLength;
    Exit;
  end;
  if (mLength > 2 * mSize) and StartsStr(AMarker, mSelected) and EndsStr(AMarker, mSelected) then
  begin
    mSelected := Copy(mSelected, mSize + 1, mLength - 2 * mSize);
    Result := mBefore + mSelected + mAfter;
    AStart := mStart;
    ALength := Length(mSelected);
    Exit;
  end;
  Result := mBefore + AMarker + mSelected + AMarker + mAfter;
  AStart := mStart + mSize;
  ALength := mLength;
end;

class function TAtlasCommentEditing.CodeBlock(const AText: string; ASelStart, ASelLength: Integer;
  out AStart, ALength: Integer): string;
var
  mStart, mLength: Integer;
  mBefore, mCode, mAfter, mOpen: string;
begin
  mStart := EnsureRange(ASelStart, 0, Length(AText));
  mLength := EnsureRange(ASelLength, 0, Length(AText) - mStart);
  mBefore := Copy(AText, 1, mStart);
  mCode := Copy(AText, mStart + 1, mLength);
  mAfter := Copy(AText, mStart + mLength + 1, MaxInt);
  // Der Zaun steht auf eigenen Zeilen; ein Umbruch am Ende der Auswahl gehört hinter den Block.
  while (mCode <> '') and IsBreak(mCode[Length(mCode)]) do
  begin
    mAfter := mCode[Length(mCode)] + mAfter;
    Delete(mCode, Length(mCode), 1);
  end;
  mOpen := cFence + CodeLanguage + LineBreak;
  if (mBefore <> '') and not IsBreak(mBefore[Length(mBefore)]) then
    mOpen := LineBreak + mOpen;
  Result := mBefore + mOpen + mCode + LineBreak + cFence;
  if (mAfter <> '') and not IsBreak(mAfter[1]) then
    Result := Result + LineBreak;
  Result := Result + mAfter;
  AStart := Length(mBefore) + Length(mOpen);
  ALength := Length(mCode);
end;

class function TAtlasCommentEditing.MentionText(const AUser: TAtlasTrackerUser): string;
begin
  Result := cMention + Trim(AUser.Login);
end;

class function TAtlasCommentEditing.UserRow(const AUser: TAtlasTrackerUser): string;
begin
  Result := MentionText(AUser);
  if Trim(AUser.Name) <> '' then
    Result := Result + ' · ' + Trim(AUser.Name);
end;

class function TAtlasCommentEditing.IssueRow(const AIssue: TAtlasTrackerIssue): string;
begin
  Result := Trim(AIssue.Key);
  if Trim(AIssue.Title) <> '' then
    Result := Result + ' · ' + Trim(AIssue.Title);
  if Trim(AIssue.State) <> '' then
    Result := Result + ' · ' + Trim(AIssue.State);
end;

{ TAtlasCommentValues }

class function TAtlasCommentValues.Create(const AIssue, ABranch, ACommit, AVersion: string): TAtlasCommentValues;
begin
  Result.Issue := Trim(AIssue);
  Result.Branch := Trim(ABranch);
  Result.Commit := Trim(ACommit);
  Result.Version := Trim(AVersion);
end;

{ TAtlasCommentSnippet }

class function TAtlasCommentSnippet.Create(const AName, AText: string): TAtlasCommentSnippet;
begin
  Result.Name := AName;
  Result.Text := AText;
end;

{ TAtlasCommentSnippets }

class function TAtlasCommentSnippets.Defaults: TArray<TAtlasCommentSnippet>;
begin
  Result := nil;
  Result := Result + [TAtlasCommentSnippet.Create('Bitte mit aktuellem Build prüfen',
    'Bitte mit dem aktuellen Build prüfen.')];
  Result := Result + [TAtlasCommentSnippet.Create('Behoben in {commit}', 'Behoben in {commit}.')];
end;

class function TAtlasCommentSnippets.DefaultJson: string;
begin
  Result := ToJson(Defaults);
end;

class function TAtlasCommentSnippets.Parse(const AJson: string; out ASnippets: TArray<TAtlasCommentSnippet>):
  Boolean;
var
  mValue, mItem: TJSONValue;
  mName, mText: string;
begin
  ASnippets := nil;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    Result := mValue is TJSONArray;
    if not Result then
      Exit;
    for mItem in TJSONArray(mValue) do
    begin
      if Length(ASnippets) >= MaxSnippets then
        Break;
      if not (mItem is TJSONObject) then
        Continue;
      mName := '';
      mText := '';
      TJSONObject(mItem).TryGetValue<string>('name', mName);
      TJSONObject(mItem).TryGetValue<string>('text', mText);
      mName := Copy(Trim(mName), 1, MaxName);
      mText := Copy(mText, 1, MaxText);
      if (mName = '') or (Trim(mText) = '') then
        Continue;
      ASnippets := ASnippets + [TAtlasCommentSnippet.Create(mName, mText)];
    end;
  finally
    mValue.Free;
  end;
end;

class function TAtlasCommentSnippets.Read(const AJson: string): TArray<TAtlasCommentSnippet>;
begin
  if not Parse(AJson, Result) then
    Result := Defaults;
end;

class function TAtlasCommentSnippets.ToJson(const ASnippets: TArray<TAtlasCommentSnippet>): string;
var
  mList: TJSONArray;
  mItem: TJSONObject;
  mSnippet: TAtlasCommentSnippet;
begin
  mList := TJSONArray.Create;
  try
    for mSnippet in ASnippets do
    begin
      mItem := TJSONObject.Create;
      mItem.AddPair('name', mSnippet.Name);
      mItem.AddPair('text', mSnippet.Text);
      mList.AddElement(mItem);
    end;
    Result := mList.ToJSON;
  finally
    mList.Free;
  end;
end;

function Placed(const AText, APlaceholder, AValue: string): string;
begin
  Result := AText;
  if AValue <> '' then
    Result := StringReplace(Result, APlaceholder, AValue, [rfReplaceAll, rfIgnoreCase]);
end;

class function TAtlasCommentSnippets.Expand(const AText: string; const AValues: TAtlasCommentValues): string;
begin
  Result := Placed(AText, '{branch}', AValues.Branch);
  Result := Placed(Result, '{commit}', AValues.Commit);
  Result := Placed(Result, '{issue}', AValues.Issue);
  Result := Placed(Result, '{version}', AValues.Version);
end;

class function TAtlasCommentSnippets.NeedsVcs(const AText: string): Boolean;
begin
  Result := ContainsText(AText, '{branch}') or ContainsText(AText, '{commit}');
end;

{ TAtlasCommentDrafts }

constructor TAtlasCommentDrafts.Create;
begin
  inherited Create;
  FEntries := TList<TEntry>.Create;
  FKind := 'Kommentar-Entwürfe';
end;

destructor TAtlasCommentDrafts.Destroy;
begin
  FEntries.Free;
  inherited;
end;

class function TAtlasCommentDrafts.TrackerKey(const ATarget: TAtlasTrackerTarget): string;
begin
  Result := TAtlasRecentIssues.TrackerKey(ATarget);
end;

function TAtlasCommentDrafts.IndexOf(const ATracker, AIssue, AField: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to FEntries.Count - 1 do
    if SameText(FEntries[mIndex].Tracker, Trim(ATracker)) and SameText(FEntries[mIndex].Issue, Trim(AIssue)) and
      SameText(FEntries[mIndex].Field, Trim(AField)) then
      Exit(mIndex);
  Result := -1;
end;

function TAtlasCommentDrafts.Get(const ATracker, AIssue, AField: string; out AText: string;
  out ASaved: TDateTime): Boolean;
var
  mIndex: Integer;
begin
  AText := '';
  ASaved := 0;
  mIndex := IndexOf(ATracker, AIssue, AField);
  Result := mIndex >= 0;
  if not Result then
    Exit;
  AText := FEntries[mIndex].Text;
  ASaved := FEntries[mIndex].Saved;
end;

procedure TAtlasCommentDrafts.Put(const ATracker, AIssue, AField, AText: string; ASaved: TDateTime);
var
  mEntry: TEntry;
begin
  if (Trim(AText) = '') or (Trim(ATracker) = '') or (Trim(AIssue) = '') or (Trim(AField) = '') then
  begin
    Delete(ATracker, AIssue, AField);
    Exit;
  end;
  Delete(ATracker, AIssue, AField);
  mEntry.Tracker := Trim(ATracker);
  mEntry.Issue := Trim(AIssue);
  mEntry.Field := Trim(AField);
  mEntry.Text := Copy(AText, 1, TAtlasTrackerDetails.MaxText);
  mEntry.Saved := ASaved;
  FEntries.Insert(0, mEntry);
  while FEntries.Count > MaxDrafts do
    FEntries.Delete(FEntries.Count - 1);
end;

function TAtlasCommentDrafts.Delete(const ATracker, AIssue, AField: string): Boolean;
var
  mIndex: Integer;
begin
  mIndex := IndexOf(ATracker, AIssue, AField);
  Result := mIndex >= 0;
  if Result then
    FEntries.Delete(mIndex);
end;

function TAtlasCommentDrafts.Count: Integer;
begin
  Result := FEntries.Count;
end;

procedure TAtlasCommentDrafts.Clear;
begin
  FEntries.Clear;
end;

function TAtlasCommentDrafts.ToJson: string;
var
  mRoot, mItem: TJSONObject;
  mList: TJSONArray;
  mEntry: TEntry;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('version', TJSONNumber.Create(Version));
    mList := TJSONArray.Create;
    mRoot.AddPair('drafts', mList);
    for mEntry in FEntries do
    begin
      mItem := TJSONObject.Create;
      mList.AddElement(mItem);
      mItem.AddPair('tracker', mEntry.Tracker);
      mItem.AddPair('issue', mEntry.Issue);
      mItem.AddPair('field', mEntry.Field);
      mItem.AddPair('text', mEntry.Text);
      if mEntry.Saved > 0 then
        mItem.AddPair('saved', DateToISO8601(mEntry.Saved, True));
    end;
    Result := mRoot.ToJSON;
  finally
    mRoot.Free;
  end;
end;

function TAtlasCommentDrafts.Parse(const AText: string): Boolean;
var
  mRoot, mList, mItem: TJSONValue;
  mObject: TJSONObject;
  mEntry: TEntry;
  mVersion: Integer;
  mSaved: string;
begin
  FEntries.Clear;
  mRoot := TJSONObject.ParseJSONValue(AText);
  try
    Result := (mRoot is TJSONObject) and TJSONObject(mRoot).TryGetValue<Integer>('version', mVersion) and
      (mVersion = Version);
    if not Result then
      Exit;
    mList := TJSONObject(mRoot).Values['drafts'];
    if not (mList is TJSONArray) then
      Exit;
    for mItem in TJSONArray(mList) do
    begin
      if FEntries.Count >= MaxDrafts then
        Break;
      if not (mItem is TJSONObject) then
        Continue;
      mObject := TJSONObject(mItem);
      mEntry := Default(TEntry);
      if not mObject.TryGetValue<string>('tracker', mEntry.Tracker) or
        not mObject.TryGetValue<string>('issue', mEntry.Issue) or
        not mObject.TryGetValue<string>('field', mEntry.Field) or
        not mObject.TryGetValue<string>('text', mEntry.Text) or (Trim(mEntry.Text) = '') or
        (Trim(mEntry.Issue) = '') or (Trim(mEntry.Tracker) = '') or (Trim(mEntry.Field) = '') then
        Continue;
      mSaved := '';
      if mObject.TryGetValue<string>('saved', mSaved) and (mSaved <> '') then
        TryISO8601ToDate(mSaved, mEntry.Saved, True);
      mEntry.Text := Copy(mEntry.Text, 1, TAtlasTrackerDetails.MaxText);
      if IndexOf(mEntry.Tracker, mEntry.Issue, mEntry.Field) < 0 then
        FEntries.Add(mEntry);
    end;
  finally
    mRoot.Free;
  end;
end;

function TAtlasCommentDrafts.LoadFromFile(const AFileName: string): TAtlasDataLoad;
begin
  FEntries.Clear;
  FKept := '';
  Result := TAtlasDataFile.Load(AFileName, FKind,
    function(const AText: string): Boolean
    begin
      Result := Parse(AText);
    end);
  if not TAtlasDataFile.Writable(Result) then
    FKept := AFileName;
  if Result <> TAtlasDataLoad.Loaded then
    FEntries.Clear;
end;

function TAtlasCommentDrafts.SaveToFile(const AFileName: string): Boolean;
begin
  Result := not SameFileName(AFileName, FKept);
  if Result then
    TAtlasDataFile.Write(AFileName, ToJson);
end;

end.
