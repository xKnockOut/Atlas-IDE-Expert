unit Atlas.Common.Index.Extractor.Patterns;

// Folgemuster für die gelernten Vorschläge (#1890): Je Anweisungsliste
// (begin … end, try-Teil, finally, except, repeat, initialization) sieht
// Collect jede Zuweisung und jeden Aufruf an und merkt, welche Anweisung
// darauf folgt.
// - Auslöser: Konstruktor "X := TFoo.Create(…)" (Schlüssel "$S := TFoo.Create"
//   und allgemein "$S := $T.Create"), Methodenaufruf "X.BeginUpdate"
//   (Schlüssel "$S.BeginUpdate") und Aufruf ohne Empfänger
//   "EnterCriticalSection(F)" (Schlüssel "EnterCriticalSection($A)").
//   Subjekt ($S) ist das Ziel der Zuweisung bzw. der Empfänger, Argument ($A)
//   das erste Argument.
// - Folge: try … finally mit den finally-Anweisungen, die Subjekt oder
//   Argument nennen (ohne beides alle, höchstens drei), und while mit einer
//   Bedingung über das Subjekt samt der letzten Anweisung des Rumpfs, die es
//   nennt. Alles andere zählt als Stelle ohne erkannte Folge.
// - Normalisiert wird über die Token: ohne Kommentare, einheitliche
//   Leerzeichen, Subjekt und Argument als $S und $A. Vorlagen mit "$" im
//   Quelltext (Hex-Zahlen, Strings) und überlange Anweisungen fallen weg.
// Reine Funktionen über dem Syntaxbaum, threadsicher.

interface

uses
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract;

type
  /// <summary>Auslösende Anweisung eines Folgemusters (#1890).</summary>
  TFollowTrigger = record
    /// <summary>Schlüssel wie in TIndexFollowPattern.Trigger, der genaueste zuerst.</summary>
    Keys: TArray<string>;
    /// <summary>Aufgerufener Ausdruck ohne Argumente wie geschrieben ("Log.Enter", "TFoo.Create"); für die Muster
    /// aus atlas.json.</summary>
    Callee: string;
    /// <summary>Normalisierter Text des Subjekts; '' ohne.</summary>
    Subject: string;
    /// <summary>Normalisierter Text des ersten Arguments; '' ohne.</summary>
    Argument: string;
    /// <summary>Klasse beim Konstruktor; '' sonst.</summary>
    TypeName: string;
  end;

  TIndexFollowPatterns = class
  public const
    cSubject = '$S';
    cArgument = '$A';
    cTypeName = '$T';
    /// <summary>Zeile der Vorlage für den Rumpf; dort steht nach dem Übernehmen die Schreibmarke.</summary>
    cBody = '$|';
    /// <summary>Je Ebene der Einrückung ein Zeichen vor der Zeile der Vorlage.</summary>
    cIndentMark = '>';
    /// <summary>Längste Anweisung, die in eine Vorlage geht.</summary>
    cMaxText = 160;
    /// <summary>Gemerkte Fundstellen je Muster und Unit.</summary>
    cMaxEvidence = 3;
    /// <summary>Höchstens so viele Anweisungen aus dem finally-Teil.</summary>
    cMaxFinally = 3;
  public
    /// <summary>Folgemuster aller Anweisungslisten unter der Wurzel von ATree, je Trigger und Folge gezählt.
    /// </summary>
    class function Collect(ATree: TSyntaxTree): TArray<TIndexFollowPattern>; static;
    /// <summary>Stehen die Kinder eines Knotens der Art AKind als Anweisungsfolge hintereinander?</summary>
    class function IsList(AKind: TSyntaxKind): Boolean; static;
    /// <summary>Ist AStatement ein Auslöser? ATrigger nennt Schlüssel, Subjekt und Argument.</summary>
    class function TriggerOf(ATree: TSyntaxTree; AStatement: TSyntaxNode; out ATrigger: TFollowTrigger): Boolean;
      static;
    /// <summary>Vorlage der Anweisung ANext nach dem Auslöser ATrigger; '' ohne erkannte Folge oder ohne ANext.
    /// </summary>
    class function FollowOf(ATree: TSyntaxTree; ANext: TSyntaxNode; const ATrigger: TFollowTrigger): string; static;
    /// <summary>Die Anweisung nach AStatement in seiner Anweisungsliste (leere übersprungen); nil am Ende oder
    /// außerhalb einer Liste.</summary>
    class function NextStatement(AStatement: TSyntaxNode): TSyntaxNode; static;
    /// <summary>Normalisierter Text des Knotens ANode: Code-Token mit einheitlichen Leerzeichen, ohne Kommentare.
    /// </summary>
    class function Text(ATree: TSyntaxTree; ANode: TSyntaxNode): string; static;
    /// <summary>Normalisierter Text der Code-Token in AText (für Vorlagen aus atlas.json).</summary>
    class function NormalizeText(const AText: string): string; static;
  end;

implementation

uses
  Atlas.Common.Pascal.Contract,
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Pascal.Lexer;

type
  /// <summary>Ein Token der Normalisierung; Marker sind $S und $A.</summary>
  TPiece = record
    Text: string;
    /// <summary>Bezeichner oder Marker: davor kein Leerzeichen vor "(" und "[".</summary>
    Name: Boolean;
    Marker: Boolean;
  end;

  TPieces = TArray<TPiece>;

function PieceOf(const AToken: TPascalToken): TPiece;
begin
  Result.Text := AToken.Text;
  Result.Name := AToken.Kind = TPascalTokenKind.Identifier;
  Result.Marker := False;
end;

function MarkerPiece(const AText: string): TPiece;
begin
  Result.Text := AText;
  Result.Name := True;
  Result.Marker := True;
end;

function IsCode(const AToken: TPascalToken): Boolean;
begin
  Result := not (AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]);
end;

/// <summary>Code-Token von ATokens mit Offset in [AStart, AEnd).</summary>
function PiecesIn(const ATokens: TArray<TPascalToken>; AFirst, AStart, AEnd: Integer): TPieces;
var
  mIndex: Integer;
begin
  Result := nil;
  mIndex := AFirst;
  while (mIndex <= High(ATokens)) and (ATokens[mIndex].Offset < AEnd) do
  begin
    if (ATokens[mIndex].Offset >= AStart) and IsCode(ATokens[mIndex]) then
    begin
      Result := Result + [PieceOf(ATokens[mIndex])];
    end;
    Inc(mIndex);
  end;
end;

function PiecesOf(ATree: TSyntaxTree; ANode: TSyntaxNode): TPieces;
begin
  Result := PiecesIn(ATree.Tokens, ATree.FirstTokenFrom(ANode.StartOffset), ANode.StartOffset, ANode.EndOffset);
end;

/// <summary>Leerzeichen zwischen APrevious und ACurrent?</summary>
function NeedsSpace(const APrevious, ACurrent: TPiece): Boolean;
begin
  if MatchStr(APrevious.Text, ['.', '(', '[', '@', '^']) then
  begin
    Exit(False);
  end;
  if MatchStr(ACurrent.Text, ['.', ',', ';', ')', ']', '^', ':']) then
  begin
    Exit(False);
  end;
  if MatchStr(ACurrent.Text, ['(', '[']) then
  begin
    Exit(not (APrevious.Name or MatchStr(APrevious.Text, [')', ']'])));
  end;
  Result := True;
end;

function Join(const APieces: TPieces): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 0 to High(APieces) do
  begin
    if (mIndex > 0) and NeedsSpace(APieces[mIndex - 1], APieces[mIndex]) then
    begin
      Result := Result + ' ';
    end;
    Result := Result + APieces[mIndex].Text;
  end;
end;

/// <summary>Stimmt AWhat ab AStart in APieces überein (ohne Groß-/Kleinschreibung, keine Marker)?</summary>
function MatchesAt(const APieces, AWhat: TPieces; AStart: Integer): Boolean;
var
  mIndex: Integer;
begin
  Result := (Length(AWhat) > 0) and (AStart + Length(AWhat) <= Length(APieces));
  mIndex := 0;
  while Result and (mIndex <= High(AWhat)) do
  begin
    Result := not APieces[AStart + mIndex].Marker and SameText(APieces[AStart + mIndex].Text, AWhat[mIndex].Text);
    Inc(mIndex);
  end;
end;

/// <summary>Ersetzt jedes Vorkommen von AWhat in APieces durch den Marker AMarker.</summary>
function Replace(const APieces, AWhat: TPieces; const AMarker: string): TPieces;
var
  mIndex: Integer;
begin
  Result := nil;
  mIndex := 0;
  while mIndex <= High(APieces) do
  begin
    if MatchesAt(APieces, AWhat, mIndex) then
    begin
      Result := Result + [MarkerPiece(AMarker)];
      Inc(mIndex, Length(AWhat));
    end
    else
    begin
      Result := Result + [APieces[mIndex]];
      Inc(mIndex);
    end;
  end;
end;

/// <summary>Taugt der normalisierte Text ATemplate für eine Vorlage: nicht leer, nicht zu lang, einzeilig und ohne
/// "$" außer den Markern?</summary>
function Usable(const APieces: TPieces; const AText: string): Boolean;
var
  mPiece: TPiece;
begin
  Result := (AText <> '') and (Length(AText) <= TIndexFollowPatterns.cMaxText) and (Pos(#10, AText) = 0) and
    (Pos(#13, AText) = 0);
  for mPiece in APieces do
  begin
    if not mPiece.Marker and (Pos('$', mPiece.Text) > 0) then
    begin
      Result := False;
    end;
  end;
end;

/// <summary>Normalisierter Text von ANode mit Subjekt und Argument als Marker; '' wenn er nicht taugt.</summary>
function TemplateText(ATree: TSyntaxTree; ANode: TSyntaxNode; const ATrigger: TFollowTrigger): string;
var
  mPieces: TPieces;
  mLexed: TArray<TPascalToken>;
  mWhat: TPieces;
  mToken: TPascalToken;
begin
  mPieces := PiecesOf(ATree, ANode);
  if ATrigger.Subject <> '' then
  begin
    mWhat := nil;
    mLexed := TPascalLexer.Tokenize(ATrigger.Subject);
    for mToken in mLexed do
    begin
      if IsCode(mToken) then
      begin
        mWhat := mWhat + [PieceOf(mToken)];
      end;
    end;
    mPieces := Replace(mPieces, mWhat, TIndexFollowPatterns.cSubject);
  end;
  if ATrigger.Argument <> '' then
  begin
    mWhat := nil;
    mLexed := TPascalLexer.Tokenize(ATrigger.Argument);
    for mToken in mLexed do
    begin
      if IsCode(mToken) then
      begin
        mWhat := mWhat + [PieceOf(mToken)];
      end;
    end;
    mPieces := Replace(mPieces, mWhat, TIndexFollowPatterns.cArgument);
  end;
  Result := Join(mPieces);
  if not Usable(mPieces, Result) then
  begin
    Result := '';
  end;
end;

function NamesTrigger(const AText: string): Boolean;
begin
  Result := (Pos(TIndexFollowPatterns.cSubject, AText) > 0) or (Pos(TIndexFollowPatterns.cArgument, AText) > 0);
end;

function StatementsOf(ANode: TSyntaxNode): TArray<TSyntaxNode>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    if ANode[mIndex].Kind <> TSyntaxKind.EmptyStatement then
    begin
      Result := Result + [ANode[mIndex]];
    end;
  end;
end;

/// <summary>Vorlage für try … finally: finally-Anweisungen, die den Auslöser nennen.</summary>
function TryFollow(ATree: TSyntaxTree; ANext: TSyntaxNode; const ATrigger: TFollowTrigger): string;
var
  mFinally, mStatement: TSyntaxNode;
  mText: string;
  mKept: Integer;
  mAll: Boolean;
begin
  Result := '';
  mFinally := ANext.FindChild(TSyntaxKind.FinallyBlock);
  if mFinally = nil then
  begin
    Exit;
  end;
  mAll := (ATrigger.Subject = '') and (ATrigger.Argument = '');
  mKept := 0;
  Result := 'try'#10 + TIndexFollowPatterns.cIndentMark + TIndexFollowPatterns.cBody + #10'finally';
  for mStatement in StatementsOf(mFinally) do
  begin
    mText := TemplateText(ATree, mStatement, ATrigger);
    if (mText <> '') and (mAll or NamesTrigger(mText)) then
    begin
      Result := Result + #10 + TIndexFollowPatterns.cIndentMark + mText + ';';
      Inc(mKept);
    end;
  end;
  if (mKept = 0) or (mKept > TIndexFollowPatterns.cMaxFinally) then
  begin
    Exit('');
  end;
  Result := Result + #10'end;';
end;

/// <summary>Vorlage für while mit Bedingung über das Subjekt und Rumpf in begin … end.</summary>
function WhileFollow(ATree: TSyntaxTree; ANext: TSyntaxNode; const ATrigger: TFollowTrigger): string;
var
  mCondition, mLast: string;
  mBody: TSyntaxNode;
  mStatements: TArray<TSyntaxNode>;
  mIndex: Integer;
begin
  Result := '';
  if (ANext.ChildCount <> 2) or (ANext[1].Kind <> TSyntaxKind.Block) then
  begin
    Exit;
  end;
  mCondition := TemplateText(ATree, ANext[0], ATrigger);
  if (mCondition = '') or not NamesTrigger(mCondition) then
  begin
    Exit;
  end;
  mBody := ANext[1];
  Result := 'while ' + mCondition + ' do';
  // begin in derselben Zeile wie do bleibt dort (Stil des Projekts).
  if mBody.StartPos.Line = ANext[0].EndPos.Line then
  begin
    Result := Result + ' begin';
  end
  else
  begin
    Result := Result + #10'begin';
  end;
  Result := Result + #10 + TIndexFollowPatterns.cIndentMark + TIndexFollowPatterns.cBody;
  mLast := '';
  mStatements := StatementsOf(mBody);
  mIndex := High(mStatements);
  while (mLast = '') and (mIndex >= 0) do
  begin
    mLast := TemplateText(ATree, mStatements[mIndex], ATrigger);
    if not NamesTrigger(mLast) then
    begin
      mLast := '';
    end;
    Dec(mIndex);
  end;
  if mLast <> '' then
  begin
    Result := Result + #10 + TIndexFollowPatterns.cIndentMark + mLast + ';';
  end;
  Result := Result + #10'end;';
end;

/// <summary>Zuweisung eines Konstruktors (X := TFoo.Create…)?</summary>
function ConstructorTrigger(ATree: TSyntaxTree; AStatement: TSyntaxNode; var ATrigger: TFollowTrigger): Boolean;
var
  mCallee: TSyntaxNode;
begin
  Result := False;
  if AStatement.ChildCount < 2 then
  begin
    Exit;
  end;
  mCallee := AStatement[1];
  if (mCallee.Kind = TSyntaxKind.Call) and (mCallee.ChildCount > 0) then
  begin
    mCallee := mCallee[0];
  end;
  if (mCallee.Kind <> TSyntaxKind.MemberAccess) or (mCallee.ChildCount < 1) or
    not StartsText('Create', mCallee.Name) then
  begin
    Exit;
  end;
  ATrigger.Subject := TIndexFollowPatterns.Text(ATree, AStatement[0]);
  ATrigger.TypeName := TIndexFollowPatterns.Text(ATree, mCallee[0]);
  ATrigger.Callee := ATrigger.TypeName + '.' + mCallee.Name;
  ATrigger.Keys := [TIndexFollowPatterns.cSubject + ' := ' + ATrigger.Callee,
    TIndexFollowPatterns.cSubject + ' := ' + TIndexFollowPatterns.cTypeName + '.' + mCallee.Name];
  Result := True;
end;

/// <summary>Aufruf mit oder ohne Empfänger (X.BeginUpdate, Log.Enter('a'), Foo(F))?</summary>
function CallTrigger(ATree: TSyntaxTree; AStatement: TSyntaxNode; var ATrigger: TFollowTrigger): Boolean;
var
  mCallee: TSyntaxNode;
begin
  Result := False;
  if AStatement.ChildCount <> 1 then
  begin
    Exit;
  end;
  mCallee := AStatement[0];
  if mCallee.Kind = TSyntaxKind.Call then
  begin
    if mCallee.ChildCount > 1 then
    begin
      ATrigger.Argument := TIndexFollowPatterns.Text(ATree, mCallee[1]);
    end;
    if mCallee.ChildCount = 0 then
    begin
      Exit;
    end;
    mCallee := mCallee[0];
  end;
  if (mCallee.Kind = TSyntaxKind.MemberAccess) and (mCallee.ChildCount >= 1) then
  begin
    ATrigger.Subject := TIndexFollowPatterns.Text(ATree, mCallee[0]);
    ATrigger.Callee := ATrigger.Subject + '.' + mCallee.Name;
    ATrigger.Keys := [TIndexFollowPatterns.cSubject + '.' + mCallee.Name];
    Result := True;
  end
  else if mCallee.Kind = TSyntaxKind.Identifier then
  begin
    ATrigger.Callee := mCallee.Name;
    if ATrigger.Argument <> '' then
    begin
      ATrigger.Keys := [mCallee.Name + '(' + TIndexFollowPatterns.cArgument + ')'];
    end
    else
    begin
      ATrigger.Keys := [mCallee.Name];
    end;
    Result := True;
  end;
end;

{ TIndexFollowPatterns }

class function TIndexFollowPatterns.IsList(AKind: TSyntaxKind): Boolean;
begin
  Result := AKind in [TSyntaxKind.Block, TSyntaxKind.TryStatement, TSyntaxKind.FinallyBlock, TSyntaxKind.ExceptBlock,
    TSyntaxKind.RepeatStatement, TSyntaxKind.InitializationSection, TSyntaxKind.FinalizationSection];
end;

class function TIndexFollowPatterns.Text(ATree: TSyntaxTree; ANode: TSyntaxNode): string;
begin
  Result := Join(PiecesOf(ATree, ANode));
end;

class function TIndexFollowPatterns.NormalizeText(const AText: string): string;
const
  // Der Lexer liest $S als Hex-Zahl; vorher durch Bezeichner ersetzt, die kein Quelltext enthält.
  cMarkers: array[0..2] of string = (cSubject, cArgument, cTypeName);
  cStandIns: array[0..2] of string = ('AtlasMarkerSubject__', 'AtlasMarkerArgument__', 'AtlasMarkerType__');
var
  mPieces: TPieces;
  mToken: TPascalToken;
  mText: string;
  mIndex, mMarker: Integer;
begin
  mText := AText;
  for mIndex := 0 to High(cMarkers) do
  begin
    mText := StringReplace(mText, cMarkers[mIndex], ' ' + cStandIns[mIndex] + ' ', [rfReplaceAll, rfIgnoreCase]);
  end;
  mPieces := nil;
  for mToken in TPascalLexer.Tokenize(mText) do
  begin
    if IsCode(mToken) then
    begin
      mMarker := IndexText(mToken.Text, cStandIns);
      if mMarker >= 0 then
      begin
        mPieces := mPieces + [MarkerPiece(cMarkers[mMarker])];
      end
      else
      begin
        mPieces := mPieces + [PieceOf(mToken)];
      end;
    end;
  end;
  Result := Join(mPieces);
end;

class function TIndexFollowPatterns.TriggerOf(ATree: TSyntaxTree; AStatement: TSyntaxNode;
  out ATrigger: TFollowTrigger): Boolean;
begin
  ATrigger := Default(TFollowTrigger);
  case AStatement.Kind of
    TSyntaxKind.AssignStatement:
      Result := ConstructorTrigger(ATree, AStatement, ATrigger);
    TSyntaxKind.CallStatement:
      Result := CallTrigger(ATree, AStatement, ATrigger);
  else
    Result := False;
  end;
  // Subjekt und Argument müssen sich als Marker ersetzen lassen.
  Result := Result and (Length(ATrigger.Subject) <= cMaxText) and (Length(ATrigger.Argument) <= cMaxText) and
    (Pos('$', ATrigger.Subject + ATrigger.Argument + ATrigger.Callee) = 0);
end;

class function TIndexFollowPatterns.FollowOf(ATree: TSyntaxTree; ANext: TSyntaxNode;
  const ATrigger: TFollowTrigger): string;
begin
  Result := '';
  if ANext = nil then
  begin
    Exit;
  end;
  if ANext.Kind = TSyntaxKind.TryStatement then
  begin
    Result := TryFollow(ATree, ANext, ATrigger);
  end
  else if ANext.Kind = TSyntaxKind.WhileStatement then
  begin
    Result := WhileFollow(ATree, ANext, ATrigger);
  end;
end;

class function TIndexFollowPatterns.NextStatement(AStatement: TSyntaxNode): TSyntaxNode;
var
  mParent: TSyntaxNode;
  mIndex: Integer;
  mFound: Boolean;
begin
  Result := nil;
  mParent := AStatement.Parent;
  if (mParent = nil) or not IsList(mParent.Kind) then
  begin
    Exit;
  end;
  mFound := False;
  for mIndex := 0 to mParent.ChildCount - 1 do
  begin
    if mFound and (mParent[mIndex].Kind <> TSyntaxKind.EmptyStatement) then
    begin
      Exit(mParent[mIndex]);
    end;
    if mParent[mIndex] = AStatement then
    begin
      mFound := True;
    end;
  end;
end;

type
  /// <summary>Zählt die Muster einer Unit je Trigger und Folge.</summary>
  TPatternCounter = class
  private
    FPositions: TDictionary<string, Integer>;
    FItems: TList<TIndexFollowPattern>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(const ATrigger, AFollow: string; ALine: Integer);
    function ToArray: TArray<TIndexFollowPattern>;
  end;

constructor TPatternCounter.Create;
begin
  inherited Create;
  FPositions := TDictionary<string, Integer>.Create;
  FItems := TList<TIndexFollowPattern>.Create;
end;

destructor TPatternCounter.Destroy;
begin
  FItems.Free;
  FPositions.Free;
  inherited;
end;

procedure TPatternCounter.Add(const ATrigger, AFollow: string; ALine: Integer);
var
  mKey: string;
  mPosition: Integer;
  mItem: TIndexFollowPattern;
begin
  mKey := LowerCase(ATrigger) + #1 + LowerCase(AFollow);
  if FPositions.TryGetValue(mKey, mPosition) then
  begin
    mItem := FItems[mPosition];
  end
  else
  begin
    mItem := Default(TIndexFollowPattern);
    mItem.Trigger := ATrigger;
    mItem.Follow := AFollow;
    mPosition := FItems.Add(mItem);
    FPositions.Add(mKey, mPosition);
  end;
  Inc(mItem.Count);
  if (AFollow <> '') and (Length(mItem.Lines) < TIndexFollowPatterns.cMaxEvidence) then
  begin
    mItem.Lines := mItem.Lines + [ALine];
  end;
  FItems[mPosition] := mItem;
end;

function TPatternCounter.ToArray: TArray<TIndexFollowPattern>;
begin
  Result := FItems.ToArray;
end;

class function TIndexFollowPatterns.Collect(ATree: TSyntaxTree): TArray<TIndexFollowPattern>;
var
  mCounter: TPatternCounter;
begin
  Result := nil;
  if (ATree = nil) or (ATree.Root = nil) then
  begin
    Exit;
  end;
  mCounter := TPatternCounter.Create;
  try
    ATree.Root.Walk(
      function(ANode: TSyntaxNode): Boolean
      var
        mStatements: TArray<TSyntaxNode>;
        mIndex: Integer;
        mTrigger: TFollowTrigger;
        mFollow, mKey: string;
        mNext: TSyntaxNode;
      begin
        Result := True;
        if not IsList(ANode.Kind) then
        begin
          Exit;
        end;
        mStatements := StatementsOf(ANode);
        for mIndex := 0 to High(mStatements) do
        begin
          if not TriggerOf(ATree, mStatements[mIndex], mTrigger) then
          begin
            Continue;
          end;
          mNext := nil;
          if mIndex < High(mStatements) then
          begin
            mNext := mStatements[mIndex + 1];
          end;
          mFollow := FollowOf(ATree, mNext, mTrigger);
          for mKey in mTrigger.Keys do
          begin
            mCounter.Add(mKey, mFollow, mStatements[mIndex].StartPos.Line);
          end;
        end;
      end);
    Result := mCounter.ToArray;
  finally
    mCounter.Free;
  end;
end;

end.
