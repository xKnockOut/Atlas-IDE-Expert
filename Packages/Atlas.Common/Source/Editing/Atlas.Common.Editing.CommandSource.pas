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
  Atlas.Text.Lines;

constructor TCommandSource.Create(const AContext: TSlashContext);
var
  Blanked: string;
begin
  inherited Create;
  Line := AContext.Line;
  FWrapUntil := AContext.WrapUntil;
  FLineBreak := TTextLines.LineBreakOf(AContext.Text);
  FLines := AContext.Text.Split([FLineBreak]);
  FCommandIndent := Indent(Line);
  FLines[Line] := StringOfChar(' ', Length(FLines[Line]));
  Blanked := string.Join(FLineBreak, FLines);
  FTree := TSyntaxTreeCache.Parse(Blanked);
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
  Index: Integer;
  Text: string;
begin
  Text := '';
  for Index := 0 to High(ALines) do
  begin
    Text := Text + Indent(Line) + ALines[Index] + FLineBreak;
  end;
  Result := TTextEdit.Create(TTextRange.Create(Line, 0, Line + 1, 0), Text);
end;

function TCommandSource.ReplaceWithLines(const ALines: array of string): TTextEdit;
var
  Index: Integer;
  Text: string;
begin
  Text := '';
  for Index := 0 to High(ALines) do
  begin
    Text := Text + ALines[Index] + FLineBreak;
  end;
  Result := TTextEdit.Create(TTextRange.Create(Line, 0, Line + 1, 0), Text);
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
  // Eigener Stapel statt Rekursion (Bericht M1): Die innerste Routine gewinnt, also wird ein Knoten erst nach
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
  Symbol: TIndexSymbol;
  Routine: TSyntaxNode;
  TypeName: string;
  Dot: Integer;
begin
  // Deklaration der Klasse um die Zeile.
  for Symbol in UnitIndex.Symbols do
  begin
    if (Symbol.Kind = TIndexSymbolKind.ClassType) and (Symbol.Range.StartPos.Line < Line) and
      (Symbol.Range.EndPos.Line > Line) then
    begin
      AClass := Symbol;
      Exit(True);
    end;
  end;
  // Methode TFoo.Bar: Klasse TFoo in derselben Datei.
  Routine := RoutineAt;
  if Routine = nil then
  begin
    Exit(False);
  end;
  Dot := LastDelimiter('.', Routine.Name);
  if Dot = 0 then
  begin
    Exit(False);
  end;
  TypeName := Copy(Routine.Name, 1, Dot - 1);
  for Symbol in UnitIndex.Symbols do
  begin
    if (Symbol.Kind = TIndexSymbolKind.ClassType) and SameText(Symbol.Name, TypeName) and (Symbol.Container = '') then
    begin
      AClass := Symbol;
      Exit(True);
    end;
  end;
  Result := False;
end;

function TCommandSource.PrivateLine(const AClass: TIndexSymbol): Integer;
var
  Index: Integer;
begin
  for Index := AClass.Range.StartPos.Line + 1 to AClass.Range.EndPos.Line - 1 do
  begin
    if SameText(Trim(FLines[Index]), 'private') then
    begin
      Exit(Index);
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
  Section, UsesNode: TSyntaxNode;
begin
  Result := -1;
  if FTree.Root = nil then
  begin
    Exit;
  end;
  Section := FTree.Root.FindChild(TSyntaxKind.ImplementationSection);
  if Section = nil then
  begin
    Exit;
  end;
  // Der fehlertolerante Parser legt den Abschnitt auch ohne das Schlüsselwort an (#294).
  if (Section.StartPos.Line > High(FLines)) or not StartsText('implementation', TrimLeft(FLines[Section.StartPos.Line]))
  then
  begin
    Exit;
  end;
  Result := Section.StartPos.Line;
  UsesNode := Section.FindChild(TSyntaxKind.UsesClause);
  if UsesNode <> nil then
  begin
    Result := UsesNode.EndPos.Line;
  end;
end;

function TCommandSource.LastMethodEnd(const AClassName: string): Integer;
var
  Section: TSyntaxNode;
  Index: Integer;
begin
  Result := -1;
  Section := FTree.Root.FindChild(TSyntaxKind.ImplementationSection);
  if Section = nil then
  begin
    Exit;
  end;
  for Index := 0 to Section.ChildCount - 1 do
  begin
    if (Section[Index].Kind = TSyntaxKind.RoutineDecl) and StartsText(AClassName + '.', Section[Index].Name) and
      (Section[Index].FindChild(TSyntaxKind.Block) <> nil) then
    begin
      Result := Section[Index].EndPos.Line;
    end;
  end;
end;

function TCommandSource.AddBody(const AClassName, ABody: string): TTextEdit;
var
  EndLine: Integer;
begin
  EndLine := LastMethodEnd(AClassName);
  if EndLine >= 0 then
  begin
    Result := AfterLine(EndLine, FLineBreak + ABody);
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
  Index: Integer;
begin
  Result := 0;
  for Index := 0 to ALine - 1 do
  begin
    Inc(Result, Length(FLines[Index]) + Length(FLineBreak));
  end;
end;

function SplitDeclaration(const AArguments: string; ASeparator: Char; out AName, AValue: string): Boolean;
var
  Index: Integer;
begin
  Index := Pos(ASeparator, AArguments);
  AName := Trim(Copy(AArguments, 1, Index - 1));
  AValue := Trim(Copy(AArguments, Index + 1, MaxInt));
  if AValue.EndsWith(';') then
  begin
    AValue := Trim(Copy(AValue, 1, Length(AValue) - 1));
  end;
  Result := (Index > 1) and IsValidIdent(AName) and (AValue <> '');
end;

function Fail(const AReason: string; out AReasonOut: string): Boolean;
begin
  AReasonOut := AReason;
  Result := False;
end;

function LogStatement(const AContext: TSlashContext; const AExpression: string): string;
var
  Call: string;
begin
  Call := '';
  if AContext.Host <> nil then
  begin
    Call := Trim(AContext.Host.Setting(AContext.Uri, TSlashSettings.LogCall));
  end;
  if Call = '' then
  begin
    Exit(Format('OutputDebugString(PChar(%s));', [AExpression]));
  end;
  if Pos('{text}', Call) > 0 then
  begin
    Result := StringReplace(Call, '{text}', AExpression, [rfReplaceAll]);
  end
  else
  begin
    Result := Call + '(' + AExpression + ')';
  end;
  if not EndsStr(';', Result) then
  begin
    Result := Result + ';';
  end;
end;

function BlockEndOfTokens(ASource: TCommandSource; ALine: Integer): Integer;
var
  Tokens: TArray<TPascalToken>;
  Index, Depth: Integer;
begin
  Tokens := ASource.Tree.Tokens;
  Depth := 0;
  for Index := 0 to High(Tokens) do
  begin
    if (Tokens[Index].StartPos.Line <= ALine) or (Tokens[Index].Kind <> TPascalTokenKind.Keyword) then
    begin
      Continue;
    end;
    if Tokens[Index].IsKeyword('begin') or Tokens[Index].IsKeyword('try') or Tokens[Index].IsKeyword('case') or
      Tokens[Index].IsKeyword('repeat') or Tokens[Index].IsKeyword('asm') then
    begin
      Inc(Depth);
    end
    else if Tokens[Index].IsKeyword('end') or Tokens[Index].IsKeyword('until') then
    begin
      if Depth = 0 then
      begin
        Exit(Tokens[Index].StartPos.Line);
      end;
      Dec(Depth);
    end
    else if (Depth = 0) and (Tokens[Index].IsKeyword('finally') or Tokens[Index].IsKeyword('except')) then
    begin
      Exit(Tokens[Index].StartPos.Line);
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
    Result := 'Die Markierung für /' + AName + ' muss im selben Block liegen und Anweisungen enthalten';
  end
  else
  begin
    Result := 'Nach /' + AName + ' stehen keine Anweisungen im Block';
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
    Exit(Fail('/' + AName + ' gilt nur im Rumpf einer Routine', AReason));
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
  Index: Integer;
  Section: TSyntaxNode;
  Indent: string;
begin
  Indent := ASource.Indent(ARoutine.StartPos.Line);
  Section := nil;
  for Index := 0 to ARoutine.ChildCount - 1 do
  begin
    if ARoutine[Index].Kind = AKind then
    begin
      Section := ARoutine[Index];
    end;
  end;
  if Section <> nil then
  begin
    Result := ASource.AfterLine(Section.EndPos.Line, Indent + '  ' + ADeclaration);
  end
  else
  begin
    Result := ASource.BeforeLine(ARoutine.FindChild(TSyntaxKind.Block).StartPos.Line,
      Indent + AKeyword + ASource.LineBreak + Indent + '  ' + ADeclaration);
  end;
end;

/// <summary>Trägt die fehlenden AUnits in das uses des Abschnitts an Zeile ALine ein.</summary>
procedure AddUses(ASource: TCommandSource; const AContext: TSlashContext; ALine: Integer;
  const AUnits: array of string; var AEdits: TArray<TTextEdit>);
var
  Used: TArray<string>;
  Index: Integer;
  Combined, Edit: TTextEdit;
  Found: Boolean;
begin
  Used := TUsesClauses.UsedUnits(ASource.Tree.Tokens);
  Combined := Default(TTextEdit);
  Found := False;
  for Index := 0 to High(AUnits) do
  begin
    if (AUnits[Index] <> '') and not TUsesClauses.IsUsed(Used, AUnits[Index], AContext.Namespaces) and
      TUsesClauses.AddUnit(ASource.Tree.Tokens, ASource.Offset(ALine), AUnits[Index], ASource.LineBreak, Edit) then
    begin
      // Alle Units landen an derselben Stelle: Texte zu einem Edit zusammenfassen.
      if not Found then
      begin
        Combined := Edit;
      end
      else if StartsStr(',', Edit.NewText) then
      begin
        Combined.NewText := Combined.NewText + Edit.NewText;
      end
      else
      begin
        // Neue uses-Klausel: "uses X;" wird "uses X, Y;".
        Combined.NewText := Copy(Combined.NewText, 1, Length(Combined.NewText) - 1) + ', ' + AUnits[Index] + ';';
      end;
      Found := True;
    end;
  end;
  if Found then
  begin
    AEdits := AEdits + [Combined];
  end;
end;

end.
