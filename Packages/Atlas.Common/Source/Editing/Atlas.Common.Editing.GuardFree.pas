unit Atlas.Common.Editing.GuardFree;

// Freigabe absichern (#489): Nach "Liste := TStringList.Create;" bietet die
// Vervollständigung an, den folgenden Code in try…finally mit Freigabe
// einzuschließen. Hier stehen die Prüfung und die Änderung ohne Protokollbezug.
//
// Angeboten wird nur, wenn
//   - die Variable lokal ist (var-Abschnitt der Routine oder Inline-Variable)
//     und ihr deklarierter Typ nicht wie ein Interface aussieht (IFoo),
//   - der erzeugte Typ laut Namensauflösung keine Record- oder Interface-Art
//     ist und kein Owner übergeben wird (Self, Application, Owner, AOwner bzw.
//     bei TComponent-Nachfahren jedes Argument außer nil),
//   - die Variable im Rest der Routine weder freigegeben noch zurückgegeben,
//     zugewiesen oder an Add, Insert, Push, Enqueue, AddObject, AddPair bzw.
//     AddOrSetValue übergeben wird (eine Liste könnte sie besitzen),
//   - die nächste Zeile mit Inhalt nicht schon mit try beginnt.
// Wie bei TCodeActions.TryFinally (#42), aber vorsichtiger: Ein falsches
// Angebot gibt ein Objekt doppelt frei.
//
// Zwei Formen: nur eine neue Zeile im try (Standard) und, wenn die Anweisung
// direkt im Rumpf der Routine steht und danach noch Zeilen folgen, alles bis
// zum Ende der Routine im try. "$0" markiert die Cursorstelle danach.
//
// Angeboten wird nach dem ";" oder nach dem Zeilenende: Fehlt das ";" (Enter
// am Zeilenende nach der Übernahme), setzt die Änderung es selbst, sofern die
// nächste Zeile den Ausdruck nicht fortsetzt. Die leere Zeile, die das Enter
// angelegt hat (BlankLine), ersetzt die Änderung.

interface

uses
  System.SysUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract;

type
  {$SCOPEDENUMS ON}
  /// <summary>Art des erzeugten Typs laut Namensauflösung.</summary>
  TGuardTypeKind = (Unknown, Class_, Component, Other);
  TGuardScope = (NewLine, ToRoutineEnd);
  {$SCOPEDENUMS OFF}

  /// <summary>Art des Typs ATypeName (ohne generische Argumente).</summary>
  TGuardTypeKindFunc = reference to function(const ATypeName: string): TGuardTypeKind;

  TGuardOffer = record
    Variable: string;
    /// <summary>Erzeugter Typ ohne generische Argumente.</summary>
    TypeName: string;
    Line: Integer;
    Indent: string;
    /// <summary>Zeile des end, das den Rumpf der Routine schließt.</summary>
    EndLine: Integer;
    /// <summary>Bis zum Routinenende einschließen ist möglich: Die Anweisung steht direkt im Rumpf, dahinter
    /// folgen Zeilen mit Inhalt, und das end steht am Anfang seiner Zeile.</summary>
    CanEnclose: Boolean;
    /// <summary>Der Anweisung fehlt das ";"; die Änderung setzt es an StatementEnd.</summary>
    AddSemicolon: Boolean;
    /// <summary>Spalte (0-basiert) hinter der schließenden Klammer bzw. dem Konstruktornamen.</summary>
    StatementEnd: Integer;
    /// <summary>Leere Zeile nach der Anweisung, die die Änderung ersetzt (Enter am Zeilenende); -1 ohne.</summary>
    BlankLine: Integer;
  end;

  TGuardFree = class
  public
    /// <summary>Passt Zeile ALine für das Angebot? AKindOf darf nil sein.</summary>
    class function Check(ATree: TSyntaxTree; const AText: string; ALine: Integer; const AKindOf: TGuardTypeKindFunc;
      out AOffer: TGuardOffer): Boolean; static;
    /// <summary>Änderung für AScope; im Text steht "$0" an der Cursorstelle.</summary>
    class function Edit(const AText: string; const AOffer: TGuardOffer; AScope: TGuardScope;
      AStyle: TCompletionFreeStyle): TTextEdit; static;
    /// <summary>Deklarierter Typ der lokalen Variable AName der Routine um Zeile ALine, deklariert vor ALine
    /// (var-Abschnitt oder Inline-Variable); False, wenn sie dort nicht lokal ist, etwa ein Feld (#42).</summary>
    class function LocalVariableType(ATree: TSyntaxTree; const AText, AName: string; ALine: Integer;
      out AType: string): Boolean; static;
  end;

implementation

uses
  System.Math,
  System.StrUtils,
  System.RegularExpressions,
  System.Generics.Collections,
  Atlas.Text.Lines;

function Covers(ANode: TSyntaxNode; ALine: Integer): Boolean;
begin
  Result := (ANode.StartPos.Line <= ALine) and (ANode.EndPos.Line >= ALine);
end;

/// <summary>Ist AChild eine Routine, deren begin…end Zeile ALine umschließt?</summary>
function IsRoutineAround(AChild: TSyntaxNode; ALine: Integer): Boolean;
var
  mBlock: TSyntaxNode;
begin
  if not Covers(AChild, ALine) or (AChild.Kind <> TSyntaxKind.RoutineDecl) then
  begin
    Exit(False);
  end;
  mBlock := AChild.FindChild(TSyntaxKind.Block);
  Result := (mBlock <> nil) and (mBlock.StartPos.Line < ALine) and (mBlock.EndPos.Line > ALine);
end;

/// <summary>Letzte passende Routine unter den Kindern von ANode; nil ohne.</summary>
function RoutineAmong(ANode: TSyntaxNode; ALine: Integer): TSyntaxNode;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    if IsRoutineAround(ANode[mIndex], ALine) then
    begin
      Result := ANode[mIndex];
    end;
  end;
end;

/// <summary>Legt ANode als erledigt und darüber seine Kinder um Zeile ALine auf den Stapel.</summary>
procedure PushCovering(APending: TStack<TSyntaxPostOrderEntry>; ANode: TSyntaxNode; ALine: Integer);
var
  mIndex: Integer;
begin
  APending.Push(TSyntaxPostOrderEntry.Create(ANode, True));
  for mIndex := ANode.ChildCount - 1 downto 0 do
  begin
    if Covers(ANode[mIndex], ALine) then
    begin
      APending.Push(TSyntaxPostOrderEntry.Create(ANode[mIndex], False));
    end;
  end;
end;

/// <summary>Innerste Routine mit Rumpf, deren begin…end Zeile ALine enthält; nil sonst.</summary>
function RoutineAt(ANode: TSyntaxNode; ALine: Integer): TSyntaxNode;
var
  mPending: TStack<TSyntaxPostOrderEntry>;
  mEntry: TSyntaxPostOrderEntry;
begin
  // Eigener Stapel statt Rekursion (Bericht M1). Die innerste Routine gewinnt: Ein Knoten wird erst geprüft,
  // wenn unter seinen Kindern keine passende Routine liegt; dann gilt die letzte passende unter ihnen.
  Result := nil;
  mPending := TStack<TSyntaxPostOrderEntry>.Create;
  try
    mPending.Push(TSyntaxPostOrderEntry.Create(ANode, False));
    while (Result = nil) and (mPending.Count > 0) do
    begin
      mEntry := mPending.Pop;
      if mEntry.Done then
      begin
        Result := RoutineAmong(mEntry.Node, ALine);
      end
      else
      begin
        PushCovering(mPending, mEntry.Node, ALine);
      end;
    end;
  finally
    mPending.Free;
  end;
end;

/// <summary>Typ hinter dem Doppelpunkt einer Deklaration "A, B: T = …;"; '' ohne.</summary>
function TypeOfDecl(const AText: string; ANode: TSyntaxNode): string;
var
  Source: string;
  Colon, Stop: Integer;
begin
  Source := Copy(AText, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
  Colon := Pos(':', Source);
  if (Colon = 0) or (Copy(Source, Colon, 2) = ':=') then
  begin
    Exit('');
  end;
  Result := Copy(Source, Colon + 1, MaxInt);
  Stop := Pos(':=', Result);
  if Stop = 0 then
  begin
    Stop := Pos('=', Result);
  end;
  if Stop > 0 then
  begin
    Result := Copy(Result, 1, Stop - 1);
  end;
  Result := Trim(StringReplace(Result, ';', '', [rfReplaceAll]));
end;

function HasName(const ANames, AName: string): Boolean;
var
  Name: string;
begin
  for Name in SplitString(ANames, ',') do
  begin
    if SameText(Trim(Name), AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Merkt den Typ, wenn ADecl AName deklariert.</summary>
procedure NoteDecl(ADecl: TSyntaxNode; const AText, AName: string; var AFound: string; var AAny: Boolean);
begin
  if HasName(ADecl.Name, AName) then
  begin
    AFound := TypeOfDecl(AText, ADecl);
    AAny := True;
  end;
end;

procedure NoteSection(ASection: TSyntaxNode; const AText, AName: string; var AFound: string; var AAny: Boolean);
var
  mIndex: Integer;
begin
  for mIndex := 0 to ASection.ChildCount - 1 do
  begin
    if ASection[mIndex].Kind = TSyntaxKind.VarDecl then
    begin
      NoteDecl(ASection[mIndex], AText, AName, AFound, AAny);
    end;
  end;
end;

/// <summary>Deklarierter Typ der lokalen Variable AName in ARoutine vor ALine; False, wenn sie nicht lokal ist.</summary>
function LocalType(ANode: TSyntaxNode; const AText, AName: string; ALine: Integer; out AType: string): Boolean;
var
  mRoot: TSyntaxNode;
  mText, mName, mFound: string;
  mLine: Integer;
  mAny: Boolean;
begin
  mRoot := ANode;
  mText := AText;
  mName := AName;
  mLine := ALine;
  mFound := '';
  mAny := False;
  // Walk statt Rekursion (Bericht M1); die letzte Deklaration vor ALine gilt. Die Kinder stehen in
  // Quelltextreihenfolge, ein Knoten hinter ALine schließt also auch seine übrigen Geschwister aus.
  ANode.Walk(
    function(AChild: TSyntaxNode): Boolean
    begin
      Result := False;
      if AChild = mRoot then
      begin
        Result := True;
      end
      else if AChild.StartPos.Line > mLine then
      begin
        Result := False;
      end
      else if AChild.Kind = TSyntaxKind.VarSection then
      begin
        NoteSection(AChild, mText, mName, mFound, mAny);
      end
      else if AChild.Kind = TSyntaxKind.InlineVar then
      begin
        NoteDecl(AChild, mText, mName, mFound, mAny);
      end
      else
      begin
        // Verschachtelte Routinen haben eigene Variablen.
        Result := AChild.Kind <> TSyntaxKind.RoutineDecl;
      end;
    end);
  Result := mAny;
  if mAny then
  begin
    AType := mFound;
  end;
end;

/// <summary>Erstes Argument auf oberster Ebene aus "(A, B(C, D))"; '' ohne.</summary>
function FirstArgument(const AArgs: string): string;
var
  Index, Depth: Integer;
begin
  Result := Trim(AArgs);
  if not StartsStr('(', Result) then
  begin
    Exit('');
  end;
  Result := Copy(Result, 2, Length(Result) - 2);
  Depth := 0;
  for Index := 1 to Length(Result) do
    case Result[Index] of
      '(', '[':
        Inc(Depth);
      ')', ']':
        Dec(Depth);
      ',':
        if Depth = 0 then
        begin
          Exit(Trim(Copy(Result, 1, Index - 1)));
        end;
    end;
  Result := Trim(Result);
end;

/// <summary>Steht die Anweisung in Zeile ALine direkt im Rumpf von ABlock (nicht in if, with usw.)?</summary>
function TopLevel(ABlock: TSyntaxNode; ALine: Integer): Boolean;
var
  Index: Integer;
begin
  for Index := 0 to ABlock.ChildCount - 1 do
  begin
    if ABlock[Index].StartPos.Line = ALine then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

type
  /// <summary>Prüfung einer Zeile für das Angebot.</summary>
  TGuardCheck = record
    Lines: TArray<string>;
    Text: string;
    Line: Integer;
    Match: TMatch;
    function Matches: Boolean;
    function StatementEnd: Integer;
    function IsLocalObject(ARoutine: TSyntaxNode): Boolean;
    function IsFreeable(const AKindOf: TGuardTypeKindFunc; const ATypeName: string): Boolean;
    function IsGuarded(AAddSemicolon: Boolean): Boolean;
    function KeepsObject(ABlock: TSyntaxNode): Boolean;
    function HasContent(AFirst, ALast: Integer): Boolean;
    procedure Fill(ABlock: TSyntaxNode; var AOffer: TGuardOffer);
    function Offers(ARoutine: TSyntaxNode; const AKindOf: TGuardTypeKindFunc; var AOffer: TGuardOffer): Boolean;
  end;

function KindOf(const AKindOf: TGuardTypeKindFunc; const ATypeName: string): TGuardTypeKind;
begin
  Result := TGuardTypeKind.Unknown;
  if Assigned(AKindOf) then
  begin
    Result := AKindOf(ATypeName);
  end;
end;

/// <summary>Beginnt die nächste Zeile mit Inhalt mit try oder setzt sie (ohne ";") den Ausdruck fort?</summary>
function StartsGuard(const ANext: string; AAddSemicolon: Boolean): Boolean;
begin
  Result := TRegEx.IsMatch(ANext, '^try\b', [roIgnoreCase]) or AAddSemicolon and TRegEx.IsMatch(ANext,
    '^([.(\[^+\-*/=<>,:]|(and|or|xor|div|mod|shl|shr|as|is|in|not)\b)', [roIgnoreCase]);
end;

{ TGuardCheck }

function TGuardCheck.Matches: Boolean;
var
  mName: string;
begin
  // Einrückung, "var ", Name, ": Typ", Klasse, Konstruktor, Argumente, ";". Leere Alternativen halten jede Gruppe
  // belegt. Erst mit ";"; ohne dürfen die Argumente
  // außerhalb von Strings kein ";" und kein "/" enthalten, sonst zählte ein Kommentar mit.
  Match := TRegEx.Match(Lines[Line], '^(\s*)(var\s+|)(\w+)\s*(:[^:=]+|):=\s*([A-Za-z_][\w.]*)(<[^;()]*>|)\s*\.\s*' +
    '(Create\w*)\s*(\(.*\)|)\s*(;)\s*(//.*|)$', [roIgnoreCase]);
  if not Match.Success then
  begin
    Match := TRegEx.Match(Lines[Line], '^(\s*)(var\s+|)(\w+)\s*(:[^:=]+|):=\s*([A-Za-z_][\w.]*)(<[^;()]*>|)\s*' +
      '\.\s*(Create\w*)\s*(\((?:[^;/'']|''[^'']*'')*\)|)\s*()(//.*|)$', [roIgnoreCase]);
  end;
  Result := Match.Success;
  if Result then
  begin
    mName := Match.Groups[3].Value;
    Result := not (SameText(mName, 'Result') or SameText(mName, 'Self'));
  end;
end;

function TGuardCheck.StatementEnd: Integer;
begin
  if Match.Groups[8].Value <> '' then
  begin
    Result := Match.Groups[8].Index + Match.Groups[8].Length - 1;
  end
  else
  begin
    Result := Match.Groups[7].Index + Match.Groups[7].Length - 1;
  end;
end;

function TGuardCheck.IsLocalObject(ARoutine: TSyntaxNode): Boolean;
var
  mDeclaredType: string;
begin
  // Lokal: Inline-Variable in dieser Zeile, sonst var-Abschnitt oder frühere Inline-Variable der Routine.
  Result := True;
  if Match.Groups[2].Value <> '' then
  begin
    mDeclaredType := Trim(Copy(Match.Groups[4].Value, 2, MaxInt));
  end
  else
  begin
    Result := LocalType(ARoutine, Text, Match.Groups[3].Value, Line - 1, mDeclaredType);
  end;
  Result := Result and not TRegEx.IsMatch(mDeclaredType, '^I[A-Z]');
end;

function TGuardCheck.IsFreeable(const AKindOf: TGuardTypeKindFunc; const ATypeName: string): Boolean;
const
  cOwners: array[0..3] of string = ('Self', 'Application', 'Owner', 'AOwner');
var
  mKind: TGuardTypeKind;
  mArgument: string;
begin
  mKind := KindOf(AKindOf, ATypeName);
  // Owner übernimmt die Freigabe.
  mArgument := FirstArgument(Match.Groups[8].Value);
  Result := (mKind <> TGuardTypeKind.Other) and not MatchText(mArgument, cOwners) and
    not ((mKind = TGuardTypeKind.Component) and (mArgument <> '') and not SameText(mArgument, 'nil'));
end;

function TGuardCheck.IsGuarded(AAddSemicolon: Boolean): Boolean;
var
  mIndex: Integer;
  mNext: string;
begin
  // Schon geschützt: Die nächste Zeile mit Inhalt beginnt mit try. Ohne ";" darf sie den Ausdruck nicht fortsetzen.
  for mIndex := Line + 1 to High(Lines) do
  begin
    mNext := Trim(Lines[mIndex]);
    if mNext <> '' then
    begin
      Exit(StartsGuard(mNext, AAddSemicolon));
    end;
  end;
  Result := False;
end;

function TGuardCheck.KeepsObject(ABlock: TSyntaxNode): Boolean;
var
  mRest, mEscaped: string;
  mIndex: Integer;
begin
  // Rest der Routine: freigegeben, zurückgegeben, zugewiesen oder an eine Liste übergeben?
  mRest := '';
  for mIndex := Line + 1 to Min(ABlock.EndPos.Line, High(Lines)) do
  begin
    mRest := mRest + Lines[mIndex] + #10;
  end;
  mEscaped := TRegEx.Escape(Match.Groups[3].Value);
  Result := TRegEx.IsMatch(mRest, '\b' + mEscaped + '\s*\.\s*(Free|DisposeOf|Destroy)\b', [roIgnoreCase]) or
    TRegEx.IsMatch(mRest, '\bFreeAndNil\s*\(\s*' + mEscaped + '\s*\)', [roIgnoreCase]) or
    TRegEx.IsMatch(mRest, ':=\s*' + mEscaped + '\s*[;)]', [roIgnoreCase]) or
    TRegEx.IsMatch(mRest, '\.\s*(Add|Insert|Push|Enqueue|AddObject|AddPair|AddOrSetValue)\s*\(([^;]*[^\w.])?' +
      mEscaped + '\s*[,)]', [roIgnoreCase]);
end;

function TGuardCheck.HasContent(AFirst, ALast: Integer): Boolean;
var
  mIndex: Integer;
begin
  for mIndex := AFirst to ALast do
  begin
    if Trim(Lines[mIndex]) <> '' then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TGuardCheck.Fill(ABlock: TSyntaxNode; var AOffer: TGuardOffer);
begin
  AOffer.Variable := Match.Groups[3].Value;
  AOffer.Line := Line;
  AOffer.Indent := Match.Groups[1].Value;
  AOffer.EndLine := ABlock.EndPos.Line;
  AOffer.CanEnclose := TopLevel(ABlock, Line) and (AOffer.EndLine <= High(Lines)) and
    TRegEx.IsMatch(Lines[AOffer.EndLine], '^\s*end\b', [roIgnoreCase]) and HasContent(Line + 1, AOffer.EndLine - 1);
end;

function TGuardCheck.Offers(ARoutine: TSyntaxNode; const AKindOf: TGuardTypeKindFunc;
  var AOffer: TGuardOffer): Boolean;
var
  mBlock: TSyntaxNode;
begin
  mBlock := ARoutine.FindChild(TSyntaxKind.Block);
  AOffer.AddSemicolon := Match.Groups[9].Value = '';
  AOffer.StatementEnd := StatementEnd;
  AOffer.TypeName := Match.Groups[5].Value;
  Result := IsLocalObject(ARoutine) and IsFreeable(AKindOf, AOffer.TypeName) and
    not IsGuarded(AOffer.AddSemicolon) and not KeepsObject(mBlock);
  if Result then
  begin
    Fill(mBlock, AOffer);
  end;
end;

class function TGuardFree.Check(ATree: TSyntaxTree; const AText: string; ALine: Integer;
  const AKindOf: TGuardTypeKindFunc; out AOffer: TGuardOffer): Boolean;
var
  mCheck: TGuardCheck;
  mRoutine: TSyntaxNode;
begin
  AOffer := Default(TGuardOffer);
  AOffer.BlankLine := -1;
  mCheck.Lines := TTextLines.SplitLines(AText);
  mCheck.Text := AText;
  mCheck.Line := ALine;
  if (ATree = nil) or (ATree.Root = nil) or (ALine < 0) or (ALine > High(mCheck.Lines)) or not mCheck.Matches then
  begin
    Exit(False);
  end;
  mRoutine := RoutineAt(ATree.Root, ALine);
  Result := (mRoutine <> nil) and mCheck.Offers(mRoutine, AKindOf, AOffer);
end;

class function TGuardFree.LocalVariableType(ATree: TSyntaxTree; const AText, AName: string; ALine: Integer;
  out AType: string): Boolean;
var
  Routine: TSyntaxNode;
begin
  AType := '';
  Result := False;
  if (ATree = nil) or (ATree.Root = nil) then
  begin
    Exit;
  end;
  Routine := RoutineAt(ATree.Root, ALine);
  if Routine <> nil then
  begin
    Result := LocalType(Routine, AText, AName, ALine - 1, AType);
  end;
end;

function ReleaseText(const AOffer: TGuardOffer; AStyle: TCompletionFreeStyle): string;
begin
  if AStyle = TCompletionFreeStyle.FreeAndNil then
  begin
    Result := 'FreeAndNil(' + AOffer.Variable + ');';
  end
  else
  begin
    Result := AOffer.Variable + '.Free;';
  end;
end;

/// <summary>Bereich für eine neue Zeile im try; die leere Zeile vom Enter wird mit ersetzt.</summary>
function NewLineRange(const ALines: TArray<string>; const AOffer: TGuardOffer; AStart: Integer): TTextRange;
begin
  if (AOffer.BlankLine > AOffer.Line) and (AOffer.BlankLine <= High(ALines)) then
  begin
    Result := TTextRange.Create(AOffer.Line, AStart, AOffer.BlankLine, Length(ALines[AOffer.BlankLine]));
  end
  else
  begin
    Result := TTextRange.Create(AOffer.Line, AStart, AOffer.Line, Length(ALines[AOffer.Line]));
  end;
end;

/// <summary>Letzte Zeile mit Inhalt in AFrom+1..ATo; AFrom ohne.</summary>
function LastContentLine(const ALines: TArray<string>; AFrom, ATo: Integer): Integer;
var
  mIndex: Integer;
begin
  Result := AFrom;
  for mIndex := AFrom + 1 to ATo do
  begin
    if Trim(ALines[mIndex]) <> '' then
    begin
      Result := mIndex;
    end;
  end;
end;

function BodyLine(const ALine: string; AIsLast: Boolean): string;
begin
  Result := '';
  if Trim(ALine) <> '' then
  begin
    Result := '  ' + ALine;
  end;
  if AIsLast then
  begin
    Result := Result + '$0';
  end;
end;

/// <summary>Zeilen bis zum Routinenende um zwei Zeichen eingerückt, Cursor hinter der letzten.</summary>
function EnclosedBody(const ALines: TArray<string>; const ALineBreak: string; const AOffer: TGuardOffer): string;
var
  mIndex, mLast: Integer;
begin
  mLast := LastContentLine(ALines, AOffer.Line, AOffer.EndLine - 1);
  Result := '';
  for mIndex := AOffer.Line + 1 to AOffer.EndLine - 1 do
  begin
    if mIndex <> AOffer.BlankLine then
    begin
      Result := Result + BodyLine(ALines[mIndex], mIndex = mLast) + ALineBreak;
    end;
  end;
end;

class function TGuardFree.Edit(const AText: string; const AOffer: TGuardOffer; AScope: TGuardScope;
  AStyle: TCompletionFreeStyle): TTextEdit;
var
  mLines: TArray<string>;
  mLineBreak, mHead, mTail: string;
  mStart: Integer;
begin
  mLines := TTextLines.SplitLines(AText);
  mLineBreak := TTextLines.LineBreakOf(AText);
  // Fehlt das ";", beginnt die Änderung hinter der Anweisung und behält einen Kommentar dahinter.
  mStart := Length(mLines[AOffer.Line]);
  mHead := '';
  if AOffer.AddSemicolon then
  begin
    mStart := AOffer.StatementEnd;
    mHead := ';' + Copy(mLines[AOffer.Line], mStart + 1, MaxInt);
  end;
  mHead := mHead + mLineBreak + AOffer.Indent + 'try' + mLineBreak;
  mTail := AOffer.Indent + 'finally' + mLineBreak + AOffer.Indent + '  ' + ReleaseText(AOffer, AStyle) + mLineBreak +
    AOffer.Indent + 'end;';
  if AScope = TGuardScope.NewLine then
  begin
    Exit(TTextEdit.Create(NewLineRange(mLines, AOffer, mStart), mHead + AOffer.Indent + '  $0' + mLineBreak + mTail));
  end;
  Result := TTextEdit.Create(TTextRange.Create(AOffer.Line, mStart, AOffer.EndLine, 0),
    mHead + EnclosedBody(mLines, mLineBreak, AOffer) + mTail + mLineBreak);
end;

end.
