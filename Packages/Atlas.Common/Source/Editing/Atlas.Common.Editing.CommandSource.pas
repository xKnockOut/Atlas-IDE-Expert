unit Atlas.Common.Editing.CommandSource;

// Gemeinsame Grundlage der Schnellbefehle (#294, #295): Text, Zeilen,
// Syntaxbaum und Index der Datei mit der Befehlszeile als Leerzeichen, damit
// der Parser sie nicht als Fehler sieht und alle Positionen gleich bleiben.
// Dazu Hilfen für Einfügestellen (Routine, Klasse, private, Ende der
// implementation) und für Argumente. Mit WrapUntil (Markierung im
// Erzeugen-Menü, #719) endet ein Umschließen vor dieser Zeile statt am
// Blockende.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Editing.Contract;

type
  /// <summary>Text, Zeilen und Baum ohne die Befehlszeile.</summary>
  TCommandSource = class
  private
    FLines: TArray<string>;
    FLineBreak: string;
    FTree: TSyntaxTree;
    FUnitIndex: TUnitIndex;
    FIndexed: Boolean;
    FCommandIndent: string;
    FWrapUntil: Integer;
    function GetUnitIndex: TUnitIndex;
  public
    Line: Integer;
    constructor Create(const AContext: TSlashContext);
    destructor Destroy; override;
    /// <summary>Einrückung der Zeile; bei der Befehlszeile die des Befehls.</summary>
    function Indent(ALine: Integer): string;
    /// <summary>Löscht die Befehlszeile samt Zeilenende.</summary>
    function RemoveCommand: TTextEdit;
    /// <summary>Ersetzt die Befehlszeile durch ALines, jede mit der Einrückung der Befehlszeile.</summary>
    function ReplaceWithIndentedLines(const ALines: array of string): TTextEdit;
    /// <summary>Ersetzt die Befehlszeile durch ALines ohne Einrückung (die Zeilen bringen sie mit).</summary>
    function ReplaceWithLines(const ALines: array of string): TTextEdit;
    /// <summary>Fügt ANewText am Ende von Zeile ALine ein.</summary>
    function AfterLine(ALine: Integer; const ANewText: string): TTextEdit;
    /// <summary>Fügt ANewText vor Zeile ALine ein.</summary>
    function BeforeLine(ALine: Integer; const ANewText: string): TTextEdit;
    /// <summary>Innerste Routine mit Rumpf, in deren begin…end die Befehlszeile steht; nil sonst.</summary>
    function RoutineAt: TSyntaxNode;
    /// <summary>Klasse, in deren Deklaration oder Methode die Befehlszeile steht.</summary>
    function ClassAt(out AClass: TIndexSymbol): Boolean;
    /// <summary>Zeile von "private" (nicht strict) in AClass; -1 ohne.</summary>
    function PrivateLine(const AClass: TIndexSymbol): Integer;
    /// <summary>Zeile, hinter der Code am Ende der implementation steht (vor initialization bzw. end.).</summary>
    function ImplementationEnd: Integer;
    /// <summary>Zeile, hinter der Deklarationen der implementation beginnen (implementation bzw. deren uses).</summary>
    function ImplementationStart: Integer;
    /// <summary>Letzte Zeile des letzten Methodenrumpfs von AClassName; -1 ohne.</summary>
    function LastMethodEnd(const AClassName: string): Integer;
    /// <summary>Rumpf hinter die letzte Methode von AClassName bzw. ans Ende der implementation.</summary>
    function AddBody(const AClassName, ABody: string): TTextEdit;
    /// <summary>Text mit der Befehlszeile als Leerzeichen.</summary>
    function Text: string;
    /// <summary>Zeichenoffset des Anfangs von Zeile ALine.</summary>
    function Offset(ALine: Integer): Integer;
    property Lines: TArray<string> read FLines;
    property LineBreak: string read FLineBreak;
    property Tree: TSyntaxTree read FTree;
    property UnitIndex: TUnitIndex read GetUnitIndex;
    /// <summary>Umschließen bis vor diese Zeile (TSlashContext.WrapUntil); 0 = bis zum Blockende.</summary>
    property WrapUntil: Integer read FWrapUntil;
  end;

  /// <summary>Rahmen für Wrap: Zeilen vor und hinter den umschlossenen Anweisungen und deren zusätzliche
  /// Einrückung.</summary>
  TWrapFrame = record
    Head: TArray<string>;
    Tail: TArray<string>;
    BodyIndent: string;
    class function Create(const AHead, ATail: array of string; const ABodyIndent: string): TWrapFrame; static;
  end;

/// <summary>"Name: Typ" bzw. "Name = Wert"; ASeparator ':' oder '='.</summary>
function SplitDeclaration(const AArguments: string; ASeparator: Char; out AName, AValue: string): Boolean;
/// <summary>Setzt AReasonOut und liefert False.</summary>
function Fail(const AReason: string; out AReasonOut: string): Boolean;
/// <summary>Anweisung, die den String-Ausdruck AExpression protokolliert: slashCommands.logCall (#304) vom
/// Host, sonst OutputDebugString(PChar(…)). Ein Routinenname bekommt den Ausdruck als Argument, {text}
/// steht für ihn.</summary>
function LogStatement(const AContext: TSlashContext; const AExpression: string): string;
/// <summary>Zeile des Tokens, das den Block um ALine schließt; -1 ohne. Für die Befehlszeile mit
/// ASource.WrapUntil (#719) diese Zeile, wenn sie im Block liegt, sonst -1.</summary>
function BlockEnd(ASource: TCommandSource; ALine: Integer): Integer;
/// <summary>Grund, wenn BlockEnd -1 liefert: Markierung über das Blockende hinaus oder keine Anweisungen.</summary>
function NoStatementsReason(ASource: TCommandSource; const AName: string): string;
/// <summary>Ersetzt Befehlszeile und folgende Anweisungen durch AFrame.Head, die um AFrame.BodyIndent
/// eingerückten Anweisungen und AFrame.Tail.</summary>
function Wrap(ASource: TCommandSource; const AName: string; const AFrame: TWrapFrame; out AEdits: TArray<TTextEdit>;
  out AReason: string): Boolean;
/// <summary>Lokale Deklaration in den Abschnitt AKind der Routine; legt ihn vor begin an.</summary>
function AddLocal(ASource: TCommandSource; ARoutine: TSyntaxNode; AKind: TSyntaxKind; const AKeyword,
  ADeclaration: string): TTextEdit;

/// <summary>Trägt die fehlenden AUnits in das uses des Abschnitts an Zeile ALine ein.</summary>
procedure AddUses(ASource: TCommandSource; const AContext: TSlashContext; ALine: Integer;
  const AUnits: array of string; var AEdits: TArray<TTextEdit>);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Editing.UsesClause,
  Atlas.Text.Lines,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TCommandSourceText = (TheSelectionForMustLie, AfterThereAreNoStatements, OnlyAppliesInTheBody);

const
  cTexts: array[TCommandSourceText] of TAtlasText = (
    (De: 'Die Markierung für /%s muss im selben Block liegen und Anweisungen enthalten';
     En: 'The selection for /%s must lie in the same block and contain statements'),
    (De: 'Nach /%s stehen keine Anweisungen im Block'; En: 'After /%s there are no statements in the block'),
    (De: '/%s gilt nur im Rumpf einer Routine'; En: '/%s only applies in the body of a routine'));

{$SCOPEDENUMS OFF}

constructor TCommandSource.Create(const AContext: TSlashContext);
var
  mBlanked: string;
begin
  inherited Create;
  Line := AContext.Line;
  FWrapUntil := AContext.WrapUntil;
  FLineBreak := TTextLines.LineBreakOf(AContext.Text);
  FLines := AContext.Text.Split([FLineBreak]);
  FCommandIndent := Indent(Line);
  FLines[Line] := StringOfChar(' ', Length(FLines[Line]));
  mBlanked := string.Join(FLineBreak, FLines);
  FTree := TSyntaxTreeCache.Parse(mBlanked);
end;

destructor TCommandSource.Destroy;
begin
  FTree.Free;
  inherited;
end;

function TCommandSource.GetUnitIndex: TUnitIndex;
begin
  if not FIndexed then
  begin
    FUnitIndex := TIndexExtractor.Extract(FTree, '');
    FIndexed := True;
  end;
  Result := FUnitIndex;
end;

function TCommandSource.Indent(ALine: Integer): string;
begin
  if (ALine = Line) and (FTree <> nil) then
  begin
    Exit(FCommandIndent);
  end;
  Result := TTextLines.IndentOf(FLines[ALine]);
end;

function TCommandSource.RemoveCommand: TTextEdit;
begin
  Result := TTextEdit.Create(TTextRange.Create(Line, 0, Line + 1, 0), '');
end;

function TCommandSource.ReplaceWithIndentedLines(const ALines: array of string): TTextEdit;
var
  mIndex: Integer;
  mText: string;
begin
  mText := '';
  for mIndex := 0 to High(ALines) do
  begin
    mText := mText + Indent(Line) + ALines[mIndex] + FLineBreak;
  end;
  Result := TTextEdit.Create(TTextRange.Create(Line, 0, Line + 1, 0), mText);
end;

function TCommandSource.ReplaceWithLines(const ALines: array of string): TTextEdit;
var
  mIndex: Integer;
  mText: string;
begin
  mText := '';
  for mIndex := 0 to High(ALines) do
  begin
    mText := mText + ALines[mIndex] + FLineBreak;
  end;
  Result := TTextEdit.Create(TTextRange.Create(Line, 0, Line + 1, 0), mText);
end;

function TCommandSource.AfterLine(ALine: Integer; const ANewText: string): TTextEdit;
begin
  Result := TTextEdit.Create(TTextRange.Create(ALine, Length(FLines[ALine]), ALine, Length(FLines[ALine])),
    FLineBreak + ANewText);
end;

function TCommandSource.BeforeLine(ALine: Integer; const ANewText: string): TTextEdit;
begin
  Result := TTextEdit.Create(TTextRange.Create(ALine, 0, ALine, 0), ANewText + FLineBreak);
end;

/// <summary>Legt ANode als erledigt und darüber seine Kinder, die ALine überdecken, auf APending.</summary>
procedure PushCovering(APending: TStack<TSyntaxPostOrderEntry>; ANode: TSyntaxNode; ALine: Integer);
var
  mIndex: Integer;
begin
  APending.Push(TSyntaxPostOrderEntry.Create(ANode, True));
  for mIndex := ANode.ChildCount - 1 downto 0 do
  begin
    if (ANode[mIndex].StartPos.Line <= ALine) and (ANode[mIndex].EndPos.Line >= ALine) then
    begin
      APending.Push(TSyntaxPostOrderEntry.Create(ANode[mIndex], False));
    end;
  end;
end;

/// <summary>ANode ist eine Routine, in deren begin…end die Zeile ALine steht.</summary>
function IsRoutineAround(ANode: TSyntaxNode; ALine: Integer): Boolean;
var
  mBlock: TSyntaxNode;
begin
  Result := False;
  if ANode.Kind = TSyntaxKind.RoutineDecl then
  begin
    mBlock := ANode.FindChild(TSyntaxKind.Block);
    Result := (mBlock <> nil) and (mBlock.StartPos.Line < ALine) and (mBlock.EndPos.Line >= ALine);
  end;
end;

function FindRoutine(ANode: TSyntaxNode; ALine: Integer): TSyntaxNode;
var
  mPending: TStack<TSyntaxPostOrderEntry>;
  mEntry: TSyntaxPostOrderEntry;
begin
  // Eigener Stapel statt Rekursion: Die innerste Routine gewinnt, also wird ein Knoten erst nach
  // seinen Kindern geprüft; unter ANode nur Knoten, die ALine überdecken.
  Result := nil;
  mPending := TStack<TSyntaxPostOrderEntry>.Create;
  try
    mPending.Push(TSyntaxPostOrderEntry.Create(ANode, False));
    while mPending.Count > 0 do
    begin
      mEntry := mPending.Pop;
      if not mEntry.Done then
      begin
        PushCovering(mPending, mEntry.Node, ALine);
      end
      else if IsRoutineAround(mEntry.Node, ALine) then
      begin
        Exit(mEntry.Node);
      end;
    end;
  finally
    mPending.Free;
  end;
end;

function TCommandSource.RoutineAt: TSyntaxNode;
begin
  Result := FindRoutine(FTree.Root, Line);
end;

function TCommandSource.ClassAt(out AClass: TIndexSymbol): Boolean;
var
  mSymbol: TIndexSymbol;
  mRoutine: TSyntaxNode;
  mTypeName: string;
  mDot: Integer;
begin
  // Deklaration der Klasse um die Zeile.
  for mSymbol in UnitIndex.Symbols do
  begin
    if (mSymbol.Kind = TIndexSymbolKind.ClassType) and (mSymbol.Range.StartPos.Line < Line) and
      (mSymbol.Range.EndPos.Line > Line) then
    begin
      AClass := mSymbol;
      Exit(True);
    end;
  end;
  // Methode TFoo.Bar: Klasse TFoo in derselben Datei.
  mRoutine := RoutineAt;
  if mRoutine = nil then
  begin
    Exit(False);
  end;
  mDot := LastDelimiter('.', mRoutine.Name);
  if mDot = 0 then
  begin
    Exit(False);
  end;
  mTypeName := Copy(mRoutine.Name, 1, mDot - 1);
  for mSymbol in UnitIndex.Symbols do
  begin
    if (mSymbol.Kind = TIndexSymbolKind.ClassType) and SameText(mSymbol.Name, mTypeName) and
      (mSymbol.Container = '') then
    begin
      AClass := mSymbol;
      Exit(True);
    end;
  end;
  Result := False;
end;

function TCommandSource.PrivateLine(const AClass: TIndexSymbol): Integer;
var
  mIndex: Integer;
begin
  for mIndex := AClass.Range.StartPos.Line + 1 to AClass.Range.EndPos.Line - 1 do
  begin
    if SameText(Trim(FLines[mIndex]), 'private') then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

/// <summary>ATokens[AIndex] ist das end vor dem Punkt am Ende der Unit.</summary>
function IsUnitEnd(const ATokens: TArray<TPascalToken>; AIndex: Integer): Boolean;
var
  mNext: Integer;
begin
  Result := False;
  if not ATokens[AIndex].IsKeyword('end') then
  begin
    Exit;
  end;
  mNext := AIndex + 1;
  while (mNext <= High(ATokens)) and (ATokens[mNext].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
  begin
    Inc(mNext);
  end;
  Result := (mNext <= High(ATokens)) and ATokens[mNext].IsSymbol('.');
end;

function TCommandSource.ImplementationEnd: Integer;
var
  mTokens: TArray<TPascalToken>;
  mIndex: Integer;
  mInImplementation: Boolean;
begin
  Result := High(FLines);
  mInImplementation := False;
  mTokens := FTree.Tokens;
  for mIndex := 0 to High(mTokens) do
  begin
    if mTokens[mIndex].Kind <> TPascalTokenKind.Keyword then
    begin
      Continue;
    end;
    if mTokens[mIndex].IsKeyword('implementation') then
    begin
      mInImplementation := True;
    end
    else if mInImplementation and (mTokens[mIndex].IsKeyword('initialization') or
      mTokens[mIndex].IsKeyword('finalization')) then
    begin
      Exit(mTokens[mIndex].StartPos.Line);
    end
    else if mInImplementation and IsUnitEnd(mTokens, mIndex) then
    begin
      Result := mTokens[mIndex].StartPos.Line;
    end;
  end;
end;

function TCommandSource.ImplementationStart: Integer;
var
  mSection, mUsesNode: TSyntaxNode;
begin
  Result := -1;
  if FTree.Root = nil then
  begin
    Exit;
  end;
  mSection := FTree.Root.FindChild(TSyntaxKind.ImplementationSection);
  if mSection = nil then
  begin
    Exit;
  end;
  // Der fehlertolerante Parser legt den Abschnitt auch ohne das Schlüsselwort an (#294).
  if (mSection.StartPos.Line > High(FLines)) or not StartsText('implementation', TrimLeft(FLines[mSection.StartPos.Line]))
  then
  begin
    Exit;
  end;
  Result := mSection.StartPos.Line;
  mUsesNode := mSection.FindChild(TSyntaxKind.UsesClause);
  if mUsesNode <> nil then
  begin
    Result := mUsesNode.EndPos.Line;
  end;
end;

function TCommandSource.LastMethodEnd(const AClassName: string): Integer;
var
  mSection: TSyntaxNode;
  mIndex: Integer;
begin
  Result := -1;
  mSection := FTree.Root.FindChild(TSyntaxKind.ImplementationSection);
  if mSection = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mSection.ChildCount - 1 do
  begin
    if (mSection[mIndex].Kind = TSyntaxKind.RoutineDecl) and StartsText(AClassName + '.', mSection[mIndex].Name) and
      (mSection[mIndex].FindChild(TSyntaxKind.Block) <> nil) then
    begin
      Result := mSection[mIndex].EndPos.Line;
    end;
  end;
end;

function TCommandSource.AddBody(const AClassName, ABody: string): TTextEdit;
var
  mEndLine: Integer;
begin
  mEndLine := LastMethodEnd(AClassName);
  if mEndLine >= 0 then
  begin
    Result := AfterLine(mEndLine, FLineBreak + ABody);
  end
  else
  begin
    Result := BeforeLine(ImplementationEnd, ABody + FLineBreak);
  end;
end;

function TCommandSource.Text: string;
begin
  Result := string.Join(FLineBreak, FLines);
end;

function TCommandSource.Offset(ALine: Integer): Integer;
var
  mIndex: Integer;
begin
  Result := 0;
  for mIndex := 0 to ALine - 1 do
  begin
    Inc(Result, Length(FLines[mIndex]) + Length(FLineBreak));
  end;
end;

function SplitDeclaration(const AArguments: string; ASeparator: Char; out AName, AValue: string): Boolean;
var
  mIndex: Integer;
begin
  mIndex := Pos(ASeparator, AArguments);
  AName := Trim(Copy(AArguments, 1, mIndex - 1));
  AValue := Trim(Copy(AArguments, mIndex + 1, MaxInt));
  if AValue.EndsWith(';') then
  begin
    AValue := Trim(Copy(AValue, 1, Length(AValue) - 1));
  end;
  Result := (mIndex > 1) and IsValidIdent(AName) and (AValue <> '');
end;

function Fail(const AReason: string; out AReasonOut: string): Boolean;
begin
  AReasonOut := AReason;
  Result := False;
end;

function LogStatement(const AContext: TSlashContext; const AExpression: string): string;
var
  mCall: string;
begin
  mCall := '';
  if AContext.Host <> nil then
  begin
    mCall := Trim(AContext.Host.Setting(AContext.Uri, TSlashSettings.cLogCall));
  end;
  if mCall = '' then
  begin
    Exit(Format('OutputDebugString(PChar(%s));', [AExpression]));
  end;
  if Pos('{text}', mCall) > 0 then
  begin
    Result := StringReplace(mCall, '{text}', AExpression, [rfReplaceAll]);
  end
  else
  begin
    Result := mCall + '(' + AExpression + ')';
  end;
  if not EndsStr(';', Result) then
  begin
    Result := Result + ';';
  end;
end;

function BlockEndOfTokens(ASource: TCommandSource; ALine: Integer): Integer;
var
  mTokens: TArray<TPascalToken>;
  mIndex, mDepth: Integer;
begin
  mTokens := ASource.Tree.Tokens;
  mDepth := 0;
  for mIndex := 0 to High(mTokens) do
  begin
    if (mTokens[mIndex].StartPos.Line <= ALine) or (mTokens[mIndex].Kind <> TPascalTokenKind.Keyword) then
    begin
      Continue;
    end;
    if mTokens[mIndex].IsKeyword('begin') or mTokens[mIndex].IsKeyword('try') or mTokens[mIndex].IsKeyword('case') or
      mTokens[mIndex].IsKeyword('repeat') or mTokens[mIndex].IsKeyword('asm') then
    begin
      Inc(mDepth);
    end
    else if mTokens[mIndex].IsKeyword('end') or mTokens[mIndex].IsKeyword('until') then
    begin
      if mDepth = 0 then
      begin
        Exit(mTokens[mIndex].StartPos.Line);
      end;
      Dec(mDepth);
    end
    else if (mDepth = 0) and (mTokens[mIndex].IsKeyword('finally') or mTokens[mIndex].IsKeyword('except')) then
    begin
      Exit(mTokens[mIndex].StartPos.Line);
    end;
  end;
  Result := -1;
end;

function BlockEnd(ASource: TCommandSource; ALine: Integer): Integer;
begin
  Result := BlockEndOfTokens(ASource, ALine);
  if (ALine <> ASource.Line) or (ASource.WrapUntil <= ALine) then
  begin
    Exit;
  end;
  // Markierung (#719): nur bis vor ihr Ende, und nur, wenn sie im Block bleibt.
  if (Result >= 0) and (ASource.WrapUntil <= Result) then
  begin
    Result := ASource.WrapUntil;
  end
  else
  begin
    Result := -1;
  end;
end;

function NoStatementsReason(ASource: TCommandSource; const AName: string): string;
begin
  if ASource.WrapUntil > ASource.Line then
  begin
    Result := cTexts[TCommandSourceText.TheSelectionForMustLie].Fmt([AName]);
  end
  else
  begin
    Result := cTexts[TCommandSourceText.AfterThereAreNoStatements].Fmt([AName]);
  end;
end;

{ TWrapFrame }

function LinesOf(const ALines: array of string): TArray<string>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(ALines));
  for mIndex := 0 to High(ALines) do
  begin
    Result[mIndex] := ALines[mIndex];
  end;
end;

class function TWrapFrame.Create(const AHead, ATail: array of string; const ABodyIndent: string): TWrapFrame;
begin
  Result.Head := LinesOf(AHead);
  Result.Tail := LinesOf(ATail);
  Result.BodyIndent := ABodyIndent;
end;

/// <summary>Zeilen ALines, jede mit AIndent davor und dem Zeilenende von ASource dahinter.</summary>
function IndentedLines(ASource: TCommandSource; const ALines: TArray<string>; const AIndent: string): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 0 to High(ALines) do
  begin
    Result := Result + AIndent + ALines[mIndex] + ASource.LineBreak;
  end;
end;

/// <summary>Anweisungen hinter der Befehlszeile bis vor AStop, um AFrame.BodyIndent eingerückt, in AFrame.</summary>
function FramedText(ASource: TCommandSource; const AFrame: TWrapFrame; AStop: Integer): string;
var
  mIndex: Integer;
  mIndent: string;
begin
  mIndent := ASource.Indent(ASource.Line);
  Result := IndentedLines(ASource, AFrame.Head, mIndent);
  for mIndex := ASource.Line + 1 to AStop - 1 do
  begin
    if Trim(ASource.Lines[mIndex]) = '' then
    begin
      Result := Result + ASource.LineBreak;
    end
    else
    begin
      Result := Result + AFrame.BodyIndent + ASource.Lines[mIndex] + ASource.LineBreak;
    end;
  end;
  Result := Result + IndentedLines(ASource, AFrame.Tail, mIndent);
end;

/// <summary>Ersetzt Befehlszeile und folgende Anweisungen durch AFrame.Head, die um AFrame.BodyIndent
/// eingerückten Anweisungen und AFrame.Tail.</summary>
function Wrap(ASource: TCommandSource; const AName: string; const AFrame: TWrapFrame; out AEdits: TArray<TTextEdit>;
  out AReason: string): Boolean;
var
  mStop, mIndex: Integer;
begin
  AEdits := nil;
  if ASource.RoutineAt = nil then
  begin
    Exit(Fail(cTexts[TCommandSourceText.OnlyAppliesInTheBody].Fmt([AName]), AReason));
  end;
  mStop := BlockEnd(ASource, ASource.Line);
  // Nur Leerzeilen bis zum Blockende zählen nicht als Anweisungen.
  mIndex := ASource.Line + 1;
  while (mStop > 0) and (mIndex < mStop) and (Trim(ASource.Lines[mIndex]) = '') do
  begin
    Inc(mIndex);
  end;
  if (mStop < 0) or (mIndex >= mStop) then
  begin
    Exit(Fail(NoStatementsReason(ASource, AName), AReason));
  end;
  AEdits := [TTextEdit.Create(TTextRange.Create(ASource.Line, 0, mStop, 0), FramedText(ASource, AFrame, mStop))];
  Result := True;
end;

/// <summary>Lokale Deklaration in den Abschnitt AKind der Routine; legt ihn vor begin an.</summary>
function AddLocal(ASource: TCommandSource; ARoutine: TSyntaxNode; AKind: TSyntaxKind; const AKeyword,
  ADeclaration: string): TTextEdit;
var
  mIndex: Integer;
  mSection: TSyntaxNode;
  mIndent: string;
begin
  mIndent := ASource.Indent(ARoutine.StartPos.Line);
  mSection := nil;
  for mIndex := 0 to ARoutine.ChildCount - 1 do
  begin
    if ARoutine[mIndex].Kind = AKind then
    begin
      mSection := ARoutine[mIndex];
    end;
  end;
  if mSection <> nil then
  begin
    Result := ASource.AfterLine(mSection.EndPos.Line, mIndent + '  ' + ADeclaration);
  end
  else
  begin
    Result := ASource.BeforeLine(ARoutine.FindChild(TSyntaxKind.Block).StartPos.Line,
      mIndent + AKeyword + ASource.LineBreak + mIndent + '  ' + ADeclaration);
  end;
end;

/// <summary>Trägt die fehlenden AUnits in das uses des Abschnitts an Zeile ALine ein.</summary>
procedure AddUses(ASource: TCommandSource; const AContext: TSlashContext; ALine: Integer;
  const AUnits: array of string; var AEdits: TArray<TTextEdit>);
var
  mUsed: TArray<string>;
  mIndex: Integer;
  mCombined, mEdit: TTextEdit;
  mFound: Boolean;
begin
  mUsed := TUsesClauses.UsedUnits(ASource.Tree.Tokens);
  mCombined := Default(TTextEdit);
  mFound := False;
  for mIndex := 0 to High(AUnits) do
  begin
    if (AUnits[mIndex] <> '') and not TUsesClauses.IsUsed(mUsed, AUnits[mIndex], AContext.Namespaces) and
      TUsesClauses.AddUnit(ASource.Tree.Tokens, ASource.Offset(ALine), AUnits[mIndex], ASource.LineBreak, mEdit) then
    begin
      // Alle Units landen an derselben Stelle: Texte zu einem Edit zusammenfassen.
      if not mFound then
      begin
        mCombined := mEdit;
      end
      else if StartsStr(',', mEdit.NewText) then
      begin
        mCombined.NewText := mCombined.NewText + mEdit.NewText;
      end
      else
      begin
        // Neue uses-Klausel: "uses X;" wird "uses X, Y;".
        mCombined.NewText := Copy(mCombined.NewText, 1, Length(mCombined.NewText) - 1) + ', ' + AUnits[mIndex] + ';';
      end;
      mFound := True;
    end;
  end;
  if mFound then
  begin
    AEdits := AEdits + [mCombined];
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Editing.CommandSource', cTexts);

end.
