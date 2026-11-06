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
    /// <summary>Vorgaben von issues.commentSnippets in der Sprache der Oberfläche: deutsch wie im Schema, mit
    /// AEnglish englisch (#1458).</summary>
    class function Defaults(AEnglish: Boolean): TArray<TAtlasCommentSnippet>; static;
    /// <summary>Vorgaben als JSON; deutsch wie im Schema.</summary>
    class function DefaultJson(AEnglish: Boolean): string; static;
    /// <summary>Liste [{"name": …, "text": …}]; Einträge ohne Name oder Text entfallen, Längen werden gekürzt.
    /// False, wenn AJson keine Liste ist.</summary>
    class function Parse(const AJson: string; out ASnippets: TArray<TAtlasCommentSnippet>): Boolean; static;
    /// <summary>Wie Parse für die Oberfläche in AEnglish: Ungültiges JSON und die unveränderten Vorgaben einer
    /// Sprache ergeben die Vorgaben in AEnglish, so folgen sie der Sprache der IDE; eine leere Liste bleibt leer.
    /// </summary>
    class function Read(const AJson: string; AEnglish: Boolean): TArray<TAtlasCommentSnippet>; static;
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
  /// <summary>Vorgaben von issues.commentSnippets je Sprache (False deutsch wie im Schema, True englisch), je
  /// Baustein Name und Text.</summary>
  cDefaultSnippets: array[Boolean, 0..1, 0..1] of string = (
    (('Bitte mit aktuellem Build prüfen', 'Bitte mit dem aktuellen Build prüfen.'), // german-ok: Vorgabe im Schema
     ('Behoben in {commit}', 'Behoben in {commit}.')),
    (('Please check with the current build', 'Please check with the current build.'),
     ('Fixed in {commit}', 'Fixed in {commit}.')));

function IsNameChar(AChar: Char): Boolean;
begin
  Result := AChar.IsLetterOrDigit or CharInSet(AChar, ['_', '.', '-']);
end;

function IsBreak(AChar: Char): Boolean;
begin
  Result := CharInSet(AChar, [#13, #10]);
end;

/// <summary>Anfang des Worts vor ACaret: Index des Zeichens davor (0 am Textanfang).</summary>
function WordStart(const AText: string; ACaret: Integer): Integer;
begin
  Result := ACaret;
  while (Result >= 1) and IsNameChar(AText[Result]) do
  begin
    Dec(Result);
  end;
end;

/// <summary>Issue-Auslöser für AWord ab AStart (wie SelStart); None, wenn die Palette nichts daraus liest.
/// </summary>
function IssueTrigger(const ATarget: TAtlasTrackerTarget; const AWord: string; AStart: Integer):
  TAtlasCommentTrigger;
var
  mQuery: TAtlasIssueSearchQuery;
begin
  Result := TAtlasCommentTrigger.None;
  mQuery := TAtlasIssuePaletteSearch.Parse(ATarget, AWord);
  if mQuery.Kind <> TAtlasIssueSearchKind.None then
  begin
    Result.Kind := TAtlasCommentTriggerKind.Issue;
    Result.Text := AWord;
    Result.Query := mQuery;
    Result.Start := AStart;
    Result.Length := Length(AWord);
  end;
end;

/// <summary>Erwähnung "@AWord"; AMarkIndex: Index des "@". Nur mit Buchstaben am Anfang.</summary>
function MentionTrigger(const AWord: string; AMarkIndex: Integer): TAtlasCommentTrigger;
begin
  Result := TAtlasCommentTrigger.None;
  if AWord[1].IsLetter then
  begin
    Result.Kind := TAtlasCommentTriggerKind.Mention;
    Result.Text := AWord;
    Result.Start := AMarkIndex - 1;
    Result.Length := Length(AWord) + 1;
  end;
end;

/// <summary>"a@b" (E-Mail), "##", "`#" und Pfade: Zeichen vor der Marke an AMarkIndex hängt daran.</summary>
function MarkIsGlued(const AText: string; AMarkIndex: Integer): Boolean;
begin
  Result := (AMarkIndex > 1) and (IsNameChar(AText[AMarkIndex - 1]) or
    CharInSet(AText[AMarkIndex - 1], [cMention, cHash, '`', '/', '\']));
end;

/// <summary>Auslöser mit "@" oder "#" an AMarkIndex vor AWord.</summary>
function MarkedTrigger(const AText: string; AMarkIndex: Integer; const AWord: string;
  const ATarget: TAtlasTrackerTarget): TAtlasCommentTrigger;
begin
  Result := TAtlasCommentTrigger.None;
  if (AWord = '') or MarkIsGlued(AText, AMarkIndex) then
  begin
    Exit;
  end;
  if AText[AMarkIndex] = cMention then
  begin
    Result := MentionTrigger(AWord, AMarkIndex);
  end
  else
  begin
    Result := IssueTrigger(ATarget, cHash + AWord, AMarkIndex - 1);
  end;
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
begin
  Result := TAtlasCommentTrigger.None;
  if (ACaret < 1) or (ACaret > System.Length(AText)) then
  begin
    Exit;
  end;
  // Mitten im Wort nicht: Die Schreibmarke steht am Ende des getippten Worts.
  if (ACaret < System.Length(AText)) and IsNameChar(AText[ACaret + 1]) then
  begin
    Exit;
  end;
  mStart := WordStart(AText, ACaret);
  mWord := Copy(AText, mStart + 1, ACaret - mStart);
  if (mStart >= 1) and CharInSet(AText[mStart], [cMention, cHash]) then
  begin
    Result := MarkedTrigger(AText, mStart, mWord, ATarget);
  end
  // Projektkürzel mit "-" (YouTrack): ein eigenes Wort, nicht Teil eines Pfads oder Codes.
  else if (mWord <> '') and not ((mStart >= 1) and CharInSet(AText[mStart], ['`', '/', '\'])) then
  begin
    Result := IssueTrigger(ATarget, mWord, mStart);
  end;
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
  begin
    Inc(ACaret);
  end;
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
  begin
    mOpen := LineBreak + mOpen;
  end;
  Result := mBefore + mOpen + mCode + LineBreak + cFence;
  if (mAfter <> '') and not IsBreak(mAfter[1]) then
  begin
    Result := Result + LineBreak;
  end;
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
  begin
    Result := Result + ' · ' + Trim(AUser.Name);
  end;
end;

class function TAtlasCommentEditing.IssueRow(const AIssue: TAtlasTrackerIssue): string;
begin
  Result := Trim(AIssue.Key);
  if Trim(AIssue.Title) <> '' then
  begin
    Result := Result + ' · ' + Trim(AIssue.Title);
  end;
  if Trim(AIssue.State) <> '' then
  begin
    Result := Result + ' · ' + Trim(AIssue.State);
  end;
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

class function TAtlasCommentSnippets.Defaults(AEnglish: Boolean): TArray<TAtlasCommentSnippet>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := Low(cDefaultSnippets[AEnglish]) to High(cDefaultSnippets[AEnglish]) do
  begin
    Result := Result + [TAtlasCommentSnippet.Create(cDefaultSnippets[AEnglish, mIndex, 0],
      cDefaultSnippets[AEnglish, mIndex, 1])];
  end;
end;

class function TAtlasCommentSnippets.DefaultJson(AEnglish: Boolean): string;
begin
  Result := ToJson(Defaults(AEnglish));
end;

/// <summary>Gleiche Bausteine in gleicher Reihenfolge.</summary>
function SameSnippets(const ALeft, ARight: TArray<TAtlasCommentSnippet>): Boolean;
var
  mIndex: Integer;
begin
  Result := Length(ALeft) = Length(ARight);
  mIndex := 0;
  while Result and (mIndex < Length(ALeft)) do
  begin
    Result := (ALeft[mIndex].Name = ARight[mIndex].Name) and (ALeft[mIndex].Text = ARight[mIndex].Text);
    Inc(mIndex);
  end;
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
    begin
      Exit;
    end;
    for mItem in TJSONArray(mValue) do
    begin
      if Length(ASnippets) >= MaxSnippets then
      begin
        Break;
      end;
      if not (mItem is TJSONObject) then
      begin
        Continue;
      end;
      mName := '';
      mText := '';
      TJSONObject(mItem).TryGetValue<string>('name', mName);
      TJSONObject(mItem).TryGetValue<string>('text', mText);
      mName := Copy(Trim(mName), 1, MaxName);
      mText := Copy(mText, 1, MaxText);
      if (mName = '') or (Trim(mText) = '') then
      begin
        Continue;
      end;
      ASnippets := ASnippets + [TAtlasCommentSnippet.Create(mName, mText)];
    end;
  finally
    mValue.Free;
  end;
end;

class function TAtlasCommentSnippets.Read(const AJson: string; AEnglish: Boolean): TArray<TAtlasCommentSnippet>;
begin
  if not Parse(AJson, Result) or SameSnippets(Result, Defaults(not AEnglish)) then
  begin
    Result := Defaults(AEnglish);
  end;
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
  begin
    Result := StringReplace(Result, APlaceholder, AValue, [rfReplaceAll, rfIgnoreCase]);
  end;
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
  begin
    if SameText(FEntries[mIndex].Tracker, Trim(ATracker)) and SameText(FEntries[mIndex].Issue, Trim(AIssue)) and
      SameText(FEntries[mIndex].Field, Trim(AField)) then
    begin
      Exit(mIndex);
    end;
  end;
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
  begin
    Exit;
  end;
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
  begin
    FEntries.Delete(FEntries.Count - 1);
  end;
end;

function TAtlasCommentDrafts.Delete(const ATracker, AIssue, AField: string): Boolean;
var
  mIndex: Integer;
begin
  mIndex := IndexOf(ATracker, AIssue, AField);
  Result := mIndex >= 0;
  if Result then
  begin
    FEntries.Delete(mIndex);
  end;
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
      begin
        mItem.AddPair('saved', DateToISO8601(mEntry.Saved, True));
      end;
    end;
    Result := mRoot.ToJSON;
  finally
    mRoot.Free;
  end;
end;

/// <summary>Pflichtfelder eines Entwurfs aus AObject; False, wenn eines fehlt.</summary>
function ReadDraftFields(AObject: TJSONObject; var AEntry: TAtlasCommentDrafts.TEntry): Boolean;
begin
  Result := AObject.TryGetValue<string>('tracker', AEntry.Tracker) and
    AObject.TryGetValue<string>('issue', AEntry.Issue) and AObject.TryGetValue<string>('field', AEntry.Field) and
    AObject.TryGetValue<string>('text', AEntry.Text);
end;

/// <summary>Kein Pflichtfeld nur Leerraum.</summary>
function IsFilledDraft(const AEntry: TAtlasCommentDrafts.TEntry): Boolean;
begin
  Result := (Trim(AEntry.Text) <> '') and (Trim(AEntry.Issue) <> '') and (Trim(AEntry.Tracker) <> '') and
    (Trim(AEntry.Field) <> '');
end;

/// <summary>Entwurf aus AItem; False bei anderer Form.</summary>
function DraftOf(AItem: TJSONValue; out AEntry: TAtlasCommentDrafts.TEntry): Boolean;
var
  mSaved: string;
begin
  AEntry := Default(TAtlasCommentDrafts.TEntry);
  Result := (AItem is TJSONObject) and ReadDraftFields(TJSONObject(AItem), AEntry) and IsFilledDraft(AEntry);
  if Result then
  begin
    mSaved := '';
    if TJSONObject(AItem).TryGetValue<string>('saved', mSaved) and (mSaved <> '') then
    begin
      TryISO8601ToDate(mSaved, AEntry.Saved, True);
    end;
    AEntry.Text := Copy(AEntry.Text, 1, TAtlasTrackerDetails.MaxText);
  end;
end;

function TAtlasCommentDrafts.Parse(const AText: string): Boolean;
var
  mRoot, mList, mItem: TJSONValue;
  mEntry: TEntry;
  mVersion: Integer;
begin
  FEntries.Clear;
  mRoot := TJSONObject.ParseJSONValue(AText);
  try
    Result := (mRoot is TJSONObject) and TJSONObject(mRoot).TryGetValue<Integer>('version', mVersion) and
      (mVersion = Version);
    if not Result then
    begin
      Exit;
    end;
    mList := TJSONObject(mRoot).Values['drafts'];
    if not (mList is TJSONArray) then
    begin
      Exit;
    end;
    for mItem in TJSONArray(mList) do
    begin
      if FEntries.Count >= MaxDrafts then
      begin
        Break;
      end;
      if DraftOf(mItem, mEntry) and (IndexOf(mEntry.Tracker, mEntry.Issue, mEntry.Field) < 0) then
      begin
        FEntries.Add(mEntry);
      end;
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
  begin
    FKept := AFileName;
  end;
  if Result <> TAtlasDataLoad.Loaded then
  begin
    FEntries.Clear;
  end;
end;

function TAtlasCommentDrafts.SaveToFile(const AFileName: string): Boolean;
begin
  Result := not SameFileName(AFileName, FKept);
  if Result then
  begin
    TAtlasDataFile.Write(AFileName, ToJson);
  end;
end;

end.
