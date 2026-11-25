unit Atlas.Core.Tracker.AiSummary;

// Issue mit KI zusammenfassen (#2462): Eingabe, Anweisung, Antwort und
// Zwischenspeicher, ohne Netz und ohne Oberfläche.
// - Eingabe: Kennung, Titel, Felder, Beschreibung, Kommentare und verknüpfte
//   Issues, soweit das Fenster „Atlas-Issue“ sie ohnehin geladen hat. Lange
//   Texte werden je Teil gekürzt; reicht der Platz nicht, bleiben der erste
//   Kommentar und die neuesten, dazwischen steht, wie viele fehlen.
// - Anweisung und Ausgabeformat fest: ein JSON-Objekt mit status,
//   openQuestions (question, who), nextStep und units.
// - Units nur, wenn es im Projekt eine Datei dazu gibt (keine erfundenen Links).
// - Zwischenspeicher je Tracker und Issue mit dem Stand (Updated und Zahl der
//   Kommentare); ändert sich das Issue, ist der Eintrag veraltet. Dazu die
//   Verbindungen, für die der Hinweis vor dem ersten Senden bestätigt ist.

interface

uses
  System.Generics.Collections,
  Atlas.Core.Tracker.Contract;

type
  TAtlasIssueSummaryQuestion = record
    Question: string;
    /// <summary>Wer antworten soll; '' unbekannt.</summary>
    Who: string;
  end;

  TAtlasIssueSummary = record
    /// <summary>Stand des Issues.</summary>
    Status: string;
    Questions: TArray<TAtlasIssueSummaryQuestion>;
    NextStep: string;
    /// <summary>Unit-Namen ohne Endung, wie das Modell sie nennt.</summary>
    Units: TArray<string>;
  end;

  /// <summary>Unit aus der Zusammenfassung, die es im Projekt gibt.</summary>
  TAtlasIssueSummaryUnit = record
    Name: string;
    Path: string;
  end;

  /// <summary>Überschriften für „Als Kommentar übernehmen“ in der Sprache der Oberfläche.</summary>
  TAtlasIssueSummaryHeads = record
    Title: string;
    Status: string;
    Questions: string;
    NextStep: string;
    Units: string;
    /// <summary>Zeile unter dem Kommentar ("Zusammengefasst mit …"); '' ohne.</summary>
    Footer: string;
  end;

  TAtlasIssueSummaries = class
  public const
    /// <summary>Höchstens so viele Zeichen Eingabe.</summary>
    cMaxInput = 24000;
    /// <summary>Höchstens so viele Zeichen je Beschreibung bzw. Kommentar.</summary>
    cMaxDescription = 8000;
    cMaxComment = 3000;
    /// <summary>Höchstens so viele Verknüpfungen.</summary>
    cMaxLinks = 30;
    /// <summary>Höchstens so viele Tokens Antwort.</summary>
    cMaxTokens = 1200;
  public
    /// <summary>Feste Anweisung; ALanguage ist die Sprache der Antwort ("German", "English").</summary>
    class function Instructions(const ALanguage: string): string; static;
    /// <summary>Inhalt der Anfrage aus ADetails, höchstens AMaxChars Zeichen (ungefähr).</summary>
    class function Input(const ADetails: TAtlasTrackerDetails; AMaxChars: Integer): string; static;
    /// <summary>Antwort des Modells lesen (auch in einem Codeblock); False ohne Stand.</summary>
    class function TryParse(const AText: string; out ASummary: TAtlasIssueSummary): Boolean; static;
    /// <summary>Units aus AUnits, zu denen es in AFiles eine .pas-Datei gibt, in der Reihenfolge von AUnits und
    /// ohne Doppelte.</summary>
    class function KnownUnits(const AUnits, AFiles: TArray<string>): TArray<TAtlasIssueSummaryUnit>; static;
    /// <summary>Zusammenfassung als Markdown für einen Kommentar.</summary>
    class function AsComment(const ASummary: TAtlasIssueSummary; const AHeads: TAtlasIssueSummaryHeads): string;
      static;
    /// <summary>Knopf in der Werkzeugleiste: ab AMinComments Kommentaren (0 = immer).</summary>
    class function ShowButton(ACommentCount, AMinComments: Integer): Boolean; static;
    /// <summary>Stand eines Issues für den Zwischenspeicher: zuletzt geändert und Zahl der Kommentare.</summary>
    class function StampOf(const ADetails: TAtlasTrackerDetails): string; static;
  end;

  TAtlasIssueSummaryCache = class
  private type
    TEntry = record
      Stamp: string;
      Summary: TAtlasIssueSummary;
    end;
  public const
    /// <summary>Höchstens so viele Issues; das älteste Eintragen fällt heraus.</summary>
    cMaxEntries = 200;
  private
    FEntries: TDictionary<string, TEntry>;
    /// <summary>Schlüssel in der Reihenfolge des Eintragens.</summary>
    FOrder: TList<string>;
    FAcknowledged: TList<string>;
    FChanged: Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Schlüssel eines Issues: Tracker und Kennung (klein).</summary>
    class function KeyOf(const ATarget: TAtlasTrackerTarget; const AKey: string): string; static;
    /// <summary>Eintrag zu AId; AStale, wenn er zu einem anderen Stand als AStamp gehört.</summary>
    function Find(const AId, AStamp: string; out ASummary: TAtlasIssueSummary; out AStale: Boolean): Boolean;
    procedure Put(const AId, AStamp: string; const ASummary: TAtlasIssueSummary);
    /// <summary>Hinweis vor dem ersten Senden für die Verbindung AConnection bestätigt?</summary>
    function Acknowledged(const AConnection: string): Boolean;
    procedure Acknowledge(const AConnection: string);
    function ToJson: string;
    /// <summary>Stand aus AJson; False bei ungültigem Text (der Speicher ist dann leer).</summary>
    function LoadJson(const AJson: string): Boolean;
    /// <summary>Seit dem letzten MarkSaved geändert.</summary>
    property Changed: Boolean read FChanged;
    procedure MarkSaved;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.DateUtils,
  Atlas.Text.Json;

const
  cCut = ' […]';
  cFence = '```';
  // Texte an den KI-Anbieter, nicht für die Oberfläche: immer englisch, die Antwortsprache steht in %s.
  cInstructions =
    'You summarize where an issue from a software project''s tracker stands, for a Delphi developer. ' +
    'Reply with exactly one JSON object and nothing else:' + sLineBreak +
    '{"status": "...", "openQuestions": [{"question": "...", "who": "..."}], "nextStep": "...", ' +
    '"units": ["Unit.Name"]}' + sLineBreak +
    '- status: two or three sentences on the current state: what is decided, done and still open.' + sLineBreak +
    '- openQuestions: questions in the discussion that nobody has answered yet, each with the person who ' +
    'should answer it ("who": a name from the discussion, "" if unclear); [] if there are none.' + sLineBreak +
    '- nextStep: the single most useful next action.' + sLineBreak +
    '- units: Delphi unit names (without .pas) that the text names as affected; only names that appear ' +
    'literally in the text; [] if none.' + sLineBreak +
    'Write the texts in %s. Do not invent facts, names or units.';
  cOmitted = '[%d comments omitted]';
  cLinkedHead = 'Linked issues:';
  cCommentsHead = 'Comments (%d, oldest first):';

/// <summary>AText höchstens AMax Zeichen, gekürzt mit Hinweis.</summary>
function Shortened(const AText: string; AMax: Integer): string;
begin
  Result := Trim(AText);
  if Length(Result) > AMax then
  begin
    Result := TrimRight(Copy(Result, 1, AMax)) + cCut;
  end;
end;

function DateOf(AValue: TDateTime): string;
begin
  Result := '';
  if AValue > 0 then
  begin
    Result := FormatDateTime('yyyy"-"mm"-"dd', AValue);
  end;
end;

function CommentBlock(const AComment: TAtlasTrackerComment): string;
var
  mHead: string;
begin
  mHead := '--- ' + AComment.Author;
  if AComment.Created > 0 then
  begin
    mHead := mHead + ', ' + DateOf(AComment.Created);
  end;
  Result := mHead + sLineBreak + Shortened(AComment.Text, TAtlasIssueSummaries.cMaxComment) + sLineBreak;
end;

function FieldsLine(const ADetails: TAtlasTrackerDetails): string;
var
  mParts: TArray<string>;
begin
  mParts := nil;
  if ADetails.State <> '' then
  begin
    mParts := mParts + ['State: ' + ADetails.State];
  end;
  if ADetails.Kind <> '' then
  begin
    mParts := mParts + ['Type: ' + ADetails.Kind];
  end;
  if ADetails.Assignee <> '' then
  begin
    mParts := mParts + ['Assignee: ' + ADetails.Assignee];
  end;
  if Length(ADetails.Labels) > 0 then
  begin
    mParts := mParts + ['Labels: ' + string.Join(', ', ADetails.Labels)];
  end;
  Result := string.Join('; ', mParts);
end;

function LinksBlock(const ALinks: TArray<TAtlasTrackerLink>): string;
var
  mIndex: Integer;
  mLine: string;
begin
  Result := '';
  for mIndex := 0 to High(ALinks) do
  begin
    if mIndex >= TAtlasIssueSummaries.cMaxLinks then
    begin
      Break;
    end;
    mLine := '- ' + ALinks[mIndex].Key + ' ' + ALinks[mIndex].Title;
    if ALinks[mIndex].Relation <> '' then
    begin
      mLine := mLine + ' (' + ALinks[mIndex].Relation + ')';
    end;
    if ALinks[mIndex].StateKnown and (ALinks[mIndex].State <> '') then
    begin
      mLine := mLine + ' [' + ALinks[mIndex].State + ']';
    end;
    Result := Result + mLine + sLineBreak;
  end;
end;

/// <summary>Kommentare, die in ABudget Zeichen passen: der erste und die neuesten; dazwischen ein Hinweis.
/// </summary>
function CommentsBlock(const AComments: TArray<TAtlasTrackerComment>; ABudget: Integer): string;
var
  mBlocks: TArray<string>;
  mTaken: TArray<Boolean>;
  mIndex, mUsed, mOmitted: Integer;
begin
  Result := '';
  SetLength(mBlocks, Length(AComments));
  SetLength(mTaken, Length(AComments));
  for mIndex := 0 to High(AComments) do
  begin
    mBlocks[mIndex] := CommentBlock(AComments[mIndex]);
    mTaken[mIndex] := False;
  end;
  mUsed := 0;
  // Der erste Kommentar beschreibt oft das Problem genauer, die neuesten den Stand.
  if (Length(mBlocks) > 0) and (Length(mBlocks[0]) <= ABudget) then
  begin
    mTaken[0] := True;
    mUsed := Length(mBlocks[0]);
  end;
  for mIndex := High(mBlocks) downto 1 do
  begin
    if mUsed + Length(mBlocks[mIndex]) > ABudget then
    begin
      Break;
    end;
    mTaken[mIndex] := True;
    Inc(mUsed, Length(mBlocks[mIndex]));
  end;
  mOmitted := 0;
  for mIndex := 0 to High(mBlocks) do
  begin
    if not mTaken[mIndex] then
    begin
      Inc(mOmitted);
      Continue;
    end;
    if mOmitted > 0 then
    begin
      Result := Result + Format(cOmitted, [mOmitted]) + sLineBreak;
      mOmitted := 0;
    end;
    Result := Result + mBlocks[mIndex];
  end;
  if mOmitted > 0 then
  begin
    Result := Result + Format(cOmitted, [mOmitted]) + sLineBreak;
  end;
end;

/// <summary>Das JSON-Objekt in AText: ohne Codeblock, vom ersten "{" bis zur letzten "}".</summary>
function ObjectText(const AText: string): string;
var
  mStart, mEnd: Integer;
begin
  Result := '';
  mStart := Pos('{', AText);
  mEnd := LastDelimiter('}', AText);
  if (mStart > 0) and (mEnd > mStart) then
  begin
    Result := Copy(AText, mStart, mEnd - mStart + 1);
  end;
end;

function QuestionsOf(AValue: TJSONValue): TArray<TAtlasIssueSummaryQuestion>;
var
  mItem: TJSONValue;
  mQuestion: TAtlasIssueSummaryQuestion;
begin
  Result := nil;
  if not (AValue is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(AValue) do
  begin
    mQuestion := Default(TAtlasIssueSummaryQuestion);
    if mItem is TJSONObject then
    begin
      mQuestion.Question := TJsonRead.TrimmedText(TJSONObject(mItem), 'question');
      mQuestion.Who := TJsonRead.TrimmedText(TJSONObject(mItem), 'who');
    end
    else if TJsonRead.IsString(mItem) then
    begin
      mQuestion.Question := Trim(mItem.Value);
    end;
    if mQuestion.Question <> '' then
    begin
      Result := Result + [mQuestion];
    end;
  end;
end;

/// <summary>Name einer Unit ohne Endung und Pfad; '' bei Zeichen, die in keinem Unit-Namen stehen.</summary>
function UnitNameOf(const AText: string): string;
var
  mChar: Char;
begin
  Result := Trim(AText);
  if SameText(ExtractFileExt(Result), '.pas') then
  begin
    Result := ChangeFileExt(Result, '');
  end;
  for mChar in Result do
  begin
    if not CharInSet(mChar, ['A'..'Z', 'a'..'z', '0'..'9', '_', '.']) then
    begin
      Exit('');
    end;
  end;
end;

/// <summary>Dateiname ohne Endung, getrennt an "\" und "/".</summary>
function BaseNameOf(const APath: string): string;
begin
  Result := Copy(APath, LastDelimiter('\/', APath) + 1, MaxInt);
  Result := ChangeFileExt(Result, '');
end;

function UnitIndex(const AItems: TArray<TAtlasIssueSummaryUnit>; const AName: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AItems) do
  begin
    if SameText(AItems[mIndex].Name, AName) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

{ TAtlasIssueSummaries }

class function TAtlasIssueSummaries.Instructions(const ALanguage: string): string;
begin
  Result := Format(cInstructions, [ALanguage]);
end;

class function TAtlasIssueSummaries.Input(const ADetails: TAtlasTrackerDetails; AMaxChars: Integer): string;
var
  mHead, mLinks, mFields: string;
begin
  mHead := 'Issue ' + ADetails.Key + ': ' + ADetails.Title + sLineBreak;
  mFields := FieldsLine(ADetails);
  if mFields <> '' then
  begin
    mHead := mHead + mFields + sLineBreak;
  end;
  mHead := mHead + sLineBreak + 'Description:' + sLineBreak +
    Shortened(ADetails.Description, cMaxDescription) + sLineBreak;
  mLinks := LinksBlock(ADetails.Links);
  if mLinks <> '' then
  begin
    mLinks := sLineBreak + cLinkedHead + sLineBreak + mLinks;
  end;
  Result := mHead;
  if Length(ADetails.Comments) > 0 then
  begin
    Result := Result + sLineBreak + Format(cCommentsHead, [Length(ADetails.Comments)]) +
      sLineBreak + CommentsBlock(ADetails.Comments, AMaxChars - Length(mHead) - Length(mLinks));
  end;
  Result := Result + mLinks;
end;

class function TAtlasIssueSummaries.TryParse(const AText: string; out ASummary: TAtlasIssueSummary): Boolean;
var
  mObject: TJSONObject;
  mUnit: string;
begin
  ASummary := Default(TAtlasIssueSummary);
  mObject := TJsonRead.ParseObject(ObjectText(StringReplace(AText, cFence, '', [rfReplaceAll])));
  if mObject = nil then
  begin
    Exit(False);
  end;
  try
    ASummary.Status := TJsonRead.TrimmedText(mObject, 'status');
    ASummary.NextStep := TJsonRead.TrimmedText(mObject, 'nextStep');
    ASummary.Questions := QuestionsOf(TJsonRead.Value(mObject, 'openQuestions'));
    for mUnit in TJsonRead.TrimmedStrings(mObject, 'units') do
    begin
      if UnitNameOf(mUnit) <> '' then
      begin
        ASummary.Units := ASummary.Units + [UnitNameOf(mUnit)];
      end;
    end;
  finally
    mObject.Free;
  end;
  Result := ASummary.Status <> '';
end;

class function TAtlasIssueSummaries.KnownUnits(const AUnits, AFiles: TArray<string>): TArray<TAtlasIssueSummaryUnit>;
var
  mName, mFile: string;
  mItem: TAtlasIssueSummaryUnit;
begin
  Result := nil;
  for mName in AUnits do
  begin
    if (UnitNameOf(mName) = '') or (UnitIndex(Result, UnitNameOf(mName)) >= 0) then
    begin
      Continue;
    end;
    for mFile in AFiles do
    begin
      if SameText(ExtractFileExt(mFile), '.pas') and SameText(BaseNameOf(mFile), UnitNameOf(mName)) then
      begin
        mItem.Name := BaseNameOf(mFile);
        mItem.Path := mFile;
        Result := Result + [mItem];
        Break;
      end;
    end;
  end;
end;

class function TAtlasIssueSummaries.AsComment(const ASummary: TAtlasIssueSummary;
  const AHeads: TAtlasIssueSummaryHeads): string;
var
  mQuestion: TAtlasIssueSummaryQuestion;
  mLine: string;
begin
  Result := '**' + AHeads.Title + '**' + sLineBreak + sLineBreak + '**' + AHeads.Status + '** ' + ASummary.Status +
    sLineBreak;
  if Length(ASummary.Questions) > 0 then
  begin
    Result := Result + sLineBreak + '**' + AHeads.Questions + '**' + sLineBreak;
    for mQuestion in ASummary.Questions do
    begin
      mLine := '- ' + mQuestion.Question;
      if mQuestion.Who <> '' then
      begin
        mLine := mLine + ' (' + mQuestion.Who + ')';
      end;
      Result := Result + mLine + sLineBreak;
    end;
  end;
  if ASummary.NextStep <> '' then
  begin
    Result := Result + sLineBreak + '**' + AHeads.NextStep + '** ' + ASummary.NextStep + sLineBreak;
  end;
  if Length(ASummary.Units) > 0 then
  begin
    Result := Result + sLineBreak + '**' + AHeads.Units + '** `' + string.Join('`, `', ASummary.Units) + '`' +
      sLineBreak;
  end;
  if AHeads.Footer <> '' then
  begin
    Result := Result + sLineBreak + '_' + AHeads.Footer + '_' + sLineBreak;
  end;
end;

class function TAtlasIssueSummaries.ShowButton(ACommentCount, AMinComments: Integer): Boolean;
begin
  Result := ACommentCount >= AMinComments;
end;

class function TAtlasIssueSummaries.StampOf(const ADetails: TAtlasTrackerDetails): string;
begin
  Result := IntToStr(Length(ADetails.Comments));
  if ADetails.Updated > 0 then
  begin
    Result := DateToISO8601(ADetails.Updated, True) + '#' + Result;
  end;
end;

{ TAtlasIssueSummaryCache }

constructor TAtlasIssueSummaryCache.Create;
begin
  inherited Create;
  FEntries := TDictionary<string, TEntry>.Create;
  FOrder := TList<string>.Create;
  FAcknowledged := TList<string>.Create;
end;

destructor TAtlasIssueSummaryCache.Destroy;
begin
  FAcknowledged.Free;
  FOrder.Free;
  FEntries.Free;
  inherited Destroy;
end;

class function TAtlasIssueSummaryCache.KeyOf(const ATarget: TAtlasTrackerTarget; const AKey: string): string;
begin
  Result := ATarget.Key + '|' + LowerCase(Trim(AKey));
end;

function TAtlasIssueSummaryCache.Find(const AId, AStamp: string; out ASummary: TAtlasIssueSummary;
  out AStale: Boolean): Boolean;
var
  mEntry: TEntry;
begin
  ASummary := Default(TAtlasIssueSummary);
  AStale := False;
  Result := FEntries.TryGetValue(AId, mEntry);
  if Result then
  begin
    ASummary := mEntry.Summary;
    AStale := mEntry.Stamp <> AStamp;
  end;
end;

procedure TAtlasIssueSummaryCache.Put(const AId, AStamp: string; const ASummary: TAtlasIssueSummary);
var
  mEntry: TEntry;
begin
  mEntry.Stamp := AStamp;
  mEntry.Summary := ASummary;
  FOrder.Remove(AId);
  FOrder.Add(AId);
  FEntries.AddOrSetValue(AId, mEntry);
  while FOrder.Count > cMaxEntries do
  begin
    FEntries.Remove(FOrder[0]);
    FOrder.Delete(0);
  end;
  FChanged := True;
end;

function TAtlasIssueSummaryCache.Acknowledged(const AConnection: string): Boolean;
begin
  Result := FAcknowledged.Contains(LowerCase(AConnection));
end;

procedure TAtlasIssueSummaryCache.Acknowledge(const AConnection: string);
begin
  if not Acknowledged(AConnection) then
  begin
    FAcknowledged.Add(LowerCase(AConnection));
    FChanged := True;
  end;
end;

function SummaryJson(const ASummary: TAtlasIssueSummary): TJSONObject;
var
  mQuestions: TJSONArray;
  mQuestion: TAtlasIssueSummaryQuestion;
  mItem: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('status', ASummary.Status);
  mQuestions := TJSONArray.Create;
  for mQuestion in ASummary.Questions do
  begin
    mItem := TJSONObject.Create;
    mItem.AddPair('question', mQuestion.Question);
    mItem.AddPair('who', mQuestion.Who);
    mQuestions.AddElement(mItem);
  end;
  Result.AddPair('openQuestions', mQuestions);
  Result.AddPair('nextStep', ASummary.NextStep);
  Result.AddPair('units', TJsonBuild.Strings(ASummary.Units));
end;

function SummaryOf(AObject: TJSONObject): TAtlasIssueSummary;
begin
  Result := Default(TAtlasIssueSummary);
  Result.Status := TJsonRead.Text(AObject, 'status');
  Result.Questions := QuestionsOf(TJsonRead.Value(AObject, 'openQuestions'));
  Result.NextStep := TJsonRead.Text(AObject, 'nextStep');
  Result.Units := TJsonRead.TrimmedStrings(AObject, 'units');
end;

function TAtlasIssueSummaryCache.ToJson: string;
var
  mRoot, mItem: TJSONObject;
  mEntries: TJSONArray;
  mId: string;
begin
  mRoot := TJSONObject.Create;
  try
    mEntries := TJSONArray.Create;
    for mId in FOrder do
    begin
      mItem := TJSONObject.Create;
      mItem.AddPair('id', mId);
      mItem.AddPair('stamp', FEntries[mId].Stamp);
      mItem.AddPair('summary', SummaryJson(FEntries[mId].Summary));
      mEntries.AddElement(mItem);
    end;
    mRoot.AddPair('entries', mEntries);
    mRoot.AddPair('acknowledged', TJsonBuild.Strings(FAcknowledged.ToArray));
    Result := mRoot.ToJSON([]);
  finally
    mRoot.Free;
  end;
end;

function TAtlasIssueSummaryCache.LoadJson(const AJson: string): Boolean;
var
  mRoot: TJSONObject;
  mItem: TJSONValue;
  mEntries: TJSONArray;
  mId: string;
begin
  FEntries.Clear;
  FOrder.Clear;
  FAcknowledged.Clear;
  mRoot := TJsonRead.ParseObject(AJson);
  Result := mRoot <> nil;
  if not Result then
  begin
    Exit;
  end;
  try
    mEntries := TJsonRead.Items(mRoot, 'entries');
    if mEntries <> nil then
    begin
      for mItem in mEntries do
      begin
        mId := TJsonRead.Text(TJsonRead.AsObject(mItem), 'id');
        if mId <> '' then
        begin
          Put(mId, TJsonRead.Text(TJsonRead.AsObject(mItem), 'stamp'),
            SummaryOf(TJsonRead.Obj(TJsonRead.AsObject(mItem), 'summary')));
        end;
      end;
    end;
    for mId in TJsonRead.TrimmedStrings(mRoot, 'acknowledged') do
    begin
      Acknowledge(mId);
    end;
  finally
    mRoot.Free;
  end;
  FChanged := False;
end;

procedure TAtlasIssueSummaryCache.MarkSaved;
begin
  FChanged := False;
end;

end.
