unit Atlas.Common.Editing.TaskCommands;

// Schnellbefehle für Tasks und parallele Verarbeitung (#322) im Rahmen aus #293:
//   /task              TTask.Run(procedure begin … end) um die folgenden Anweisungen;
//                      VCL-Zugriffe am Ende kommen in TThread.Queue
//   /parallel          for-Schleife darunter als TParallel.For; abgelehnt bei Break/Exit,
//                      Schreiben äußerer Variablen und VCL-Zugriffen
//   /future Name: Typ  TTask.Future<Typ> um die folgenden Anweisungen
//   /atomic            Inc/Dec bzw. F := F ± N auf einem Feld als TInterlocked
// VCL-Zugriffe erkennt der Befehl an Application, Screen, den Dialogen und an
// Variablen bzw. Feldern mit bekannten VCL-Typen (wie die Regel thread-vcl-access, #148).

interface

uses
  Atlas.Common.Editing.Contract;

/// <summary>Trägt /task, /parallel, /future und /atomic über ARegister ein.</summary>
procedure RegisterTaskCommands(const ARegister: TSlashRegister);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.DeclaredTypes,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.LanguageFeatures,
  Atlas.Common.Index.Contract,
  Atlas.Common.Editing.CommandSource,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TTaskCommandsText = (OnlyAppliesInTheBody, LineTouchesVCLObjectsAnd, LinesToTouchVCLObjects, IsWrittenInTheTask,
    TheBodyWritesTheOuter, IsNotPossibleInTParallel, TParallelForOnlyCountsUpwards, PleasePutTheBodyOf,
    ParallelOnlyAppliesInThe, ExpectedIsFutureNameType, AtomicOnlyAppliesInThe, BelowAtomicThereIsNo,
    BelowAtomicThereIsNo2, ExpectedBelowIsIncF, IsNotAFieldAtomic, LineTouchesVCLObjects, ForLoopBelowAsTParallel,
    FollowingStatementsAsTTaskFuture, IncDecOnAField, FollowingStatementsInTTaskRun, FutureSumInteger,
    BelowParallelThereIsNo);

const
  cTexts: array[TTaskCommandsText] of TAtlasText = (
    (De: '/%s gilt nur im Rumpf einer Routine'; En: '/%s only applies in the body of a routine'),
    (De: 'Zeile %d fasst VCL-Objekte an und läuft jetzt über TThread.Queue im Hauptthread';
     En: 'Line %d touches VCL objects and now runs via TThread.Queue in the main thread'),
    (De: 'Zeilen %d bis %d fassen VCL-Objekte an und laufen jetzt über TThread.Queue im Hauptthread';
     En: 'Lines %d to %d touch VCL objects and now run via TThread.Queue in the main thread'),
    (De: '%s wird im Task geschrieben und danach gelesen; der Task läuft nebenläufig, der Wert steht dort nicht ' +
      'sicher fest';
     En: '%s is written in the task and read afterwards; the task runs concurrently, so the value is not reliably ' +
      'set there'),
    (De: 'Der Rumpf schreibt die äußere Variable %s; TInterlocked verwenden';
     En: 'The body writes the outer variable %s; use TInterlocked'),
    (De: ' ist in TParallel.For nicht möglich'; En: ' is not possible in TParallel.For'),
    (De: 'TParallel.For zählt nur aufwärts (kein downto)'; En: 'TParallel.For only counts upwards (no downto)'),
    (De: 'Rumpf der Schleife bitte auf eigene Zeilen setzen'; En: 'Please put the body of the loop on its own lines'),
    (De: '/parallel gilt nur im Rumpf einer Routine'; En: '/parallel only applies in the body of a routine'),
    (De: 'Erwartet wird /future Name: Typ'; En: 'Expected is /future Name: Type'),
    (De: '/atomic gilt nur im Rumpf einer Routine'; En: '/atomic only applies in the body of a routine'),
    (De: 'Unter /atomic steht keine Anweisung'; En: 'Below /atomic there is no statement'),
    (De: 'Unter /atomic steht keine einzeilige Anweisung'; En: 'Below /atomic there is no single-line statement'),
    (De: 'Erwartet wird darunter Inc(F), Dec(F) oder F := F + N';
     En: 'Expected below is Inc(F), Dec(F) or F := F + N'),
    (De: '%s ist kein Feld; /atomic gilt für Felder'; En: '%s is not a field; /atomic applies to fields'),
    (De: 'Zeile %d fasst VCL-Objekte an'; En: 'Line %d touches VCL objects'),
    (De: 'for-Schleife darunter als TParallel.For'; En: 'for loop below as TParallel.For'),
    (De: 'Folgende Anweisungen als TTask.Future'; En: 'Following statements as TTask.Future'),
    (De: 'Inc/Dec auf einem Feld als TInterlocked'; En: 'Inc/Dec on a field as TInterlocked'),
    (De: 'Folgende Anweisungen in TTask.Run'; En: 'Following statements in TTask.Run'),
    (De: '/future Summe: Integer'; En: '/future Sum: Integer'),
    (De: 'Unter /parallel steht keine Schleife for I := A to B do';
     En: 'Below /parallel there is no loop for I := A to B do'));

{$SCOPEDENUMS OFF}

type
  TTokens = TArray<TPascalToken>;

const
  cVclNames: array[0..6] of string = ('Application', 'Screen', 'Mouse', 'ShowMessage', 'ShowMessageFmt',
    'MessageDlg', 'ShowMessagePos');
  cVclTypes: array[0..31] of string = ('TLabel', 'TEdit', 'TMemo', 'TButton', 'TBitBtn', 'TSpeedButton', 'TListBox',
    'TComboBox', 'TCheckBox', 'TRadioButton', 'TPanel', 'TProgressBar', 'TStatusBar', 'TForm', 'TFrame', 'TImage',
    'TListView', 'TTreeView', 'TStringGrid', 'TDrawGrid', 'TDBGrid', 'TRichEdit', 'TPageControl', 'TTabSheet',
    'TToolBar', 'TTrackBar', 'TScrollBox', 'TGroupBox', 'TMaskEdit', 'TCanvas', 'TControl', 'TWinControl');

/// <summary>Typ des Felds AName im Unit-Index; '' ohne. Bei gleichnamigen Feldern gilt das letzte.</summary>
function FieldTypeOf(ASource: TCommandSource; const AName: string): string;
var
  mSymbol: TIndexSymbol;
begin
  Result := '';
  for mSymbol in ASource.UnitIndex.Symbols do
  begin
    if (mSymbol.Kind = TIndexSymbolKind.Field) and SameText(mSymbol.Name, AName) then
    begin
      Result := mSymbol.TypeName;
    end;
  end;
end;

/// <summary>Ist ATypeName ein bekannter VCL-Typ oder ein TCustom…Control?</summary>
function IsVclType(const ATypeName: string): Boolean;
begin
  Result := MatchText(ATypeName, cVclTypes) or (StartsText('TCustom', ATypeName) and EndsText('Control', ATypeName));
end;

/// <summary>Steht der Bezeichner AName an APosition für ein VCL-Objekt (globaler Name, Variable oder Feld)?</summary>
function IsVclName(ASource: TCommandSource; ATypes: TDeclaredTypes; const AName: string;
  const APosition: TTextPosition): Boolean;
var
  mTypeName: string;
begin
  if MatchText(AName, cVclNames) then
  begin
    Exit(True);
  end;
  mTypeName := ATypes.DeclaredType(AName, APosition);
  if mTypeName = '' then
  begin
    mTypeName := FieldTypeOf(ASource, AName);
  end;
  Result := IsVclType(mTypeName);
end;

/// <summary>Fasst die Zeile AText VCL-Objekte an? Bezeichner werden an APosition aufgelöst.</summary>
function TouchesVcl(ASource: TCommandSource; ATypes: TDeclaredTypes; const AText: string;
  const APosition: TTextPosition): Boolean;
var
  mToken: TPascalToken;
begin
  for mToken in TPascalLexer.Tokenize(AText) do
  begin
    if (mToken.Kind = TPascalTokenKind.Identifier) and IsVclName(ASource, ATypes, mToken.Text, APosition) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Zeilen AFirst..ALast, jede nichtleere mit APrefix vor dem Text ab Spalte ACut + 1; leere bleiben
/// leer.</summary>
function IndentedLines(ASource: TCommandSource; AFirst, ALast: Integer; const APrefix: string; ACut: Integer): string;
var
  mLine: Integer;
begin
  Result := '';
  for mLine := AFirst to ALast do
  begin
    if Trim(ASource.Lines[mLine]) = '' then
    begin
      Result := Result + ASource.LineBreak;
    end
    else
    begin
      Result := Result + APrefix + Copy(ASource.Lines[mLine], ACut + 1, MaxInt) + ASource.LineBreak;
    end;
  end;
end;

/// <summary>Zeilen der Anweisungen nach dem Befehl bis vor das Blockende; False ohne.</summary>
function FollowingLines(ASource: TCommandSource; const AName: string; out AFirst, ALast: Integer;
  out AReason: string): Boolean;
var
  mStop, mIndex: Integer;
begin
  if ASource.RoutineAt = nil then
  begin
    Exit(Fail(cTexts[TTaskCommandsText.OnlyAppliesInTheBody].Fmt([AName]), AReason));
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
  AFirst := ASource.Line + 1;
  ALast := mStop - 1;
  Result := True;
end;

{ /task }

type
  /// <summary>Offener Knoten in LocalNames; InSection = im var-Abschnitt der Routine.</summary>
  TLocalNamesEntry = record
    Node: TSyntaxNode;
    InSection: Boolean;
  end;

function LocalNamesEntry(ANode: TSyntaxNode; AInSection: Boolean): TLocalNamesEntry;
begin
  Result.Node := ANode;
  Result.InSection := AInSection;
end;

/// <summary>Nimmt AName in ANames auf, wenn er nicht leer und noch nicht enthalten ist.</summary>
procedure AddName(var ANames: TArray<string>; const AName: string);
begin
  if (AName <> '') and not MatchText(AName, ANames) then
  begin
    ANames := ANames + [AName];
  end;
end;

/// <summary>Ist AEntry eine lokale Variable: im var-Abschnitt der Routine oder inline deklariert?</summary>
function IsLocalVariable(const AEntry: TLocalNamesEntry): Boolean;
begin
  Result := ((AEntry.Node.Kind = TSyntaxKind.VarDecl) and AEntry.InSection) or
    (AEntry.Node.Kind = TSyntaxKind.InlineVar);
end;

/// <summary>Legt die Kinder von AEntry rückwärts auf APending; der var-Abschnitt von ARoutine markiert sie.</summary>
procedure PushChildren(APending: TStack<TLocalNamesEntry>; const AEntry: TLocalNamesEntry; ARoutine: TSyntaxNode);
var
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  mNode := AEntry.Node;
  for mIndex := mNode.ChildCount - 1 downto 0 do
  begin
    APending.Push(LocalNamesEntry(mNode[mIndex],
      AEntry.InSection or ((mNode = ARoutine) and (mNode[mIndex].Kind = TSyntaxKind.VarSection))));
  end;
end;

/// <summary>Lokale Variablen von ARoutine: var-Abschnitt und Inline-Variablen vor Zeile ABefore.</summary>
function LocalNames(ARoutine: TSyntaxNode; ABefore: Integer): TArray<string>;
var
  mPending: TStack<TLocalNamesEntry>;
  mEntry: TLocalNamesEntry;
begin
  // Eigener Stapel statt Rekursion, in derselben Reihenfolge.
  Result := nil;
  mPending := TStack<TLocalNamesEntry>.Create;
  try
    mPending.Push(LocalNamesEntry(ARoutine, False));
    while mPending.Count > 0 do
    begin
      mEntry := mPending.Pop;
      if mEntry.Node.StartPos.Line >= ABefore then
      begin
        Continue;
      end;
      if IsLocalVariable(mEntry) then
      begin
        AddName(Result, mEntry.Node.Name);
      end;
      // Anonyme Methoden und lokale Routinen haben eigene Variablen.
      if (mEntry.Node = ARoutine) or
        not (mEntry.Node.Kind in [TSyntaxKind.AnonymousMethod, TSyntaxKind.RoutineDecl]) then
      begin
        PushChildren(mPending, mEntry, ARoutine);
      end;
    end;
  finally
    mPending.Free;
  end;
end;

/// <summary>Einfacher Name, dem das Token AIndex (:=) zuweist, wenn mit ihm die Anweisung beginnt; sonst ''.</summary>
function AssignedName(const ATokens: TTokens; AIndex: Integer): string;
var
  mPrev: Integer;
begin
  Result := '';
  if (AIndex = 0) or not ATokens[AIndex].IsSymbol(':=') then
  begin
    Exit;
  end;
  mPrev := AIndex - 1;
  if (ATokens[mPrev].Kind = TPascalTokenKind.Identifier) and ((mPrev = 0) or ATokens[mPrev - 1].IsSymbol(';') or
    (ATokens[mPrev - 1].Kind = TPascalTokenKind.Keyword)) then
  begin
    Result := ATokens[mPrev].Text;
  end;
end;

/// <summary>Bezeichner im ersten Argument von Inc/Dec am Token AIndex; sonst ''.</summary>
function IncDecName(const ATokens: TTokens; AIndex: Integer): string;
begin
  Result := '';
  if MatchText(ATokens[AIndex].Text, ['Inc', 'Dec']) and (AIndex + 2 <= High(ATokens)) and
    ATokens[AIndex + 1].IsSymbol('(') and (ATokens[AIndex + 2].Kind = TPascalTokenKind.Identifier) then
  begin
    Result := ATokens[AIndex + 2].Text;
  end;
end;

/// <summary>Ziele der Zuweisungen und von Inc/Dec in ATokens.</summary>
function WrittenNames(const ATokens: TTokens): TArray<string>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to High(ATokens) do
  begin
    AddName(Result, AssignedName(ATokens, mIndex));
    AddName(Result, IncDecName(ATokens, mIndex));
  end;
end;

function LinesText(ASource: TCommandSource; AFirst, ALast: Integer): string;
var
  mLine: Integer;
begin
  Result := '';
  for mLine := AFirst to ALast do
  begin
    Result := Result + ASource.Lines[mLine] + #10;
  end;
end;

/// <summary>Lokale Variablen, die in den Zeilen AFirst..ALast (dem Task) geschrieben und nach ALast in der Routine
/// noch gelesen werden (#143): Der Task läuft nebenläufig, das Lesen sieht den Wert nicht sicher.</summary>
function ReadAfterTask(ASource: TCommandSource; ARoutine: TSyntaxNode; AFirst, ALast: Integer): TArray<string>;
var
  mLocals, mWritten: TArray<string>;
  mAfter: TTokens;
  mName: string;
  mIndex: Integer;
begin
  Result := nil;
  mLocals := LocalNames(ARoutine, ASource.Line);
  mWritten := WrittenNames(TPascalLexer.Tokenize(LinesText(ASource, AFirst, ALast)));
  if ALast + 1 > ARoutine.EndPos.Line then
  begin
    Exit;
  end;
  mAfter := TPascalLexer.Tokenize(LinesText(ASource, ALast + 1, ARoutine.EndPos.Line));
  for mName in mWritten do
  begin
    if not MatchText(mName, mLocals) then
    begin
      Continue;
    end;
    for mIndex := 0 to High(mAfter) do
    begin
      if (mAfter[mIndex].Kind = TPascalTokenKind.Identifier) and SameText(mAfter[mIndex].Text, mName) and
        ((mIndex = High(mAfter)) or not mAfter[mIndex + 1].IsSymbol(':=')) then
      begin
        Result := Result + [mName];
        Break;
      end;
    end;
  end;
end;

/// <summary>Erste Zeile im Bereich AFirst..ALast, ab der bis zum Ende nur VCL-Zeilen (und Leerzeilen) folgen;
/// führende Leerzeilen davon gehören noch zum Task. ALast + 1 ohne solche Zeilen.</summary>
function VclSplit(ASource: TCommandSource; AFirst, ALast: Integer): Integer;
var
  mTypes: TDeclaredTypes;
begin
  mTypes := TDeclaredTypes.Create(ASource.Tree, ASource.Text);
  try
    Result := ALast + 1;
    while (Result > AFirst) and ((Trim(ASource.Lines[Result - 1]) = '') or
      TouchesVcl(ASource, mTypes, ASource.Lines[Result - 1], TTextPosition.Create(Result - 1, 0))) do
    begin
      Dec(Result);
    end;
  finally
    mTypes.Free;
  end;
  while (Result <= ALast) and (Trim(ASource.Lines[Result]) = '') do
  begin
    Inc(Result);
  end;
end;

/// <summary>Neuer Text: AFirst..ASplit - 1 in TTask.Run, ASplit..ALast darin in TThread.Queue.</summary>
function TaskText(ASource: TCommandSource; AFirst, ASplit, ALast: Integer): string;
var
  mIndent, mLB: string;
begin
  mIndent := ASource.Indent(ASource.Line);
  mLB := ASource.LineBreak;
  Result := mIndent + 'TTask.Run(' + mLB + mIndent + '  procedure' + mLB + mIndent + '  begin' + mLB +
    IndentedLines(ASource, AFirst, ASplit - 1, '    ', 0);
  if ASplit <= ALast then
  begin
    Result := Result + mIndent + '    TThread.Queue(nil,' + mLB + mIndent + '      procedure' + mLB + mIndent +
      '      begin' + mLB + IndentedLines(ASource, ASplit, ALast, '        ', 0) + mIndent + '      end);' + mLB;
  end;
  Result := Result + mIndent + '  end);' + mLB;
end;

/// <summary>Hinweise: welche Zeilen in den Hauptthread wandern und welche Variablen danach gelesen werden.</summary>
function TaskNotes(ASource: TCommandSource; AFirst, ASplit, ALast: Integer): TArray<string>;
var
  mReadAfter: TArray<string>;
begin
  Result := nil;
  if ASplit = ALast then
  begin
    Result := Result + [cTexts[TTaskCommandsText.LineTouchesVCLObjectsAnd].Fmt([ASplit + 1])];
  end
  else if ASplit < ALast then
  begin
    Result := Result + [cTexts[TTaskCommandsText.LinesToTouchVCLObjects].Fmt([ASplit + 1, ALast + 1])];
  end;
  mReadAfter := ReadAfterTask(ASource, ASource.RoutineAt, AFirst, ALast);
  if Length(mReadAfter) > 0 then
  begin
    Result := Result + [cTexts[TTaskCommandsText.IsWrittenInTheTask].Fmt([string.Join(', ', mReadAfter)])];
  end;
end;

/// <summary>Meldet ANotes nach dem Einfügen über den Host; ohne Host oder Hinweise nichts.</summary>
procedure NotifyTask(const AContext: TSlashContext; const ANotes: TArray<string>);
var
  mHost: ISlashHost;
  mUri, mText: string;
begin
  mHost := AContext.Host;
  if (mHost = nil) or (Length(ANotes) = 0) then
  begin
    Exit;
  end;
  mUri := AContext.Uri;
  mText := '/task: ' + string.Join('. ', ANotes) + '.';
  AContext.Defer(
    procedure
    begin
      mHost.Notify(mUri, mText);
    end);
end;

function ExecuteTask(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mFirst, mLast, mSplit: Integer;
begin
  AEdits := nil;
  mSource := TCommandSource.Create(AContext);
  try
    Result := FollowingLines(mSource, 'task', mFirst, mLast, AReason);
    if Result then
    begin
      // VCL-Zeilen am Ende kommen in TThread.Queue.
      mSplit := VclSplit(mSource, mFirst, mLast);
      AEdits := [TTextEdit.Create(TTextRange.Create(mSource.Line, 0, mLast + 1, 0),
        TaskText(mSource, mFirst, mSplit, mLast))];
      AddUses(mSource, AContext, mSource.Line, ['System.Threading', 'System.Classes'], AEdits);
      NotifyTask(AContext, TaskNotes(mSource, mFirst, mSplit, mLast));
    end;
  finally
    mSource.Free;
  end;
end;

{ /parallel }

function FindFor(ANode: TSyntaxNode; ALine: Integer): TSyntaxNode;
var
  mRoot: TSyntaxNode;
  mLine: Integer;
begin
  mRoot := ANode;
  mLine := ALine;
  // Search statt Rekursion; unter ANode nur Knoten, die ALine überdecken.
  Result := ANode.Search(
    function(ACandidate: TSyntaxNode): TSyntaxSearchStep
    begin
      if (ACandidate <> mRoot) and ((ACandidate.StartPos.Line > mLine) or (ACandidate.EndPos.Line < mLine)) then
      begin
        Exit(TSyntaxSearchStep.Skip);
      end;
      Result := TSyntaxSearchStep.Descend;
      if (ACandidate.Kind = TSyntaxKind.ForStatement) and (ACandidate.StartPos.Line = mLine) then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end);
end;

/// <summary>Quelltext von ANode aus ALines.</summary>
function NodeText(const ALines: TArray<string>; ANode: TSyntaxNode): string;
var
  mLine: Integer;
begin
  if ANode.StartPos.Line = ANode.EndPos.Line then
  begin
    Exit(Copy(ALines[ANode.StartPos.Line], ANode.StartPos.Character + 1,
      ANode.EndPos.Character - ANode.StartPos.Character));
  end;
  Result := Copy(ALines[ANode.StartPos.Line], ANode.StartPos.Character + 1, MaxInt);
  for mLine := ANode.StartPos.Line + 1 to ANode.EndPos.Line - 1 do
  begin
    Result := Result + ' ' + Trim(ALines[mLine]);
  end;
  Result := Result + ' ' + Trim(Copy(ALines[ANode.EndPos.Line], 1, ANode.EndPos.Character));
end;

/// <summary>Grund, wenn eine der Zeilen AFirst..ALast VCL-Objekte anfasst; sonst ''.</summary>
function VclProblem(ASource: TCommandSource; ATypes: TDeclaredTypes; AFirst, ALast: Integer): string;
var
  mLine: Integer;
begin
  Result := '';
  for mLine := AFirst to ALast do
  begin
    if TouchesVcl(ASource, ATypes, ASource.Lines[mLine], TTextPosition.Create(mLine, 0)) then
    begin
      Exit(cTexts[TTaskCommandsText.LineTouchesVCLObjects].Fmt([mLine + 1]));
    end;
  end;
end;

function OuterWriteProblem(const AName: string): string;
begin
  Result := cTexts[TTaskCommandsText.TheBodyWritesTheOuter].Fmt([AName]);
end;

/// <summary>Folgt auf das Token AIndex ein Punkt (Zugriff auf ein Element)?</summary>
function FollowedByDot(const ATokens: TTokens; AIndex: Integer): Boolean;
begin
  Result := (AIndex < High(ATokens)) and ATokens[AIndex + 1].IsSymbol('.');
end;

/// <summary>Grund, warum das Token AIndex nicht parallel laufen darf; '' wenn es darf. Inline-Variablen
/// kommen nach ALocals.</summary>
function TokenProblem(const ATokens: TTokens; AIndex: Integer; var ALocals: TArray<string>): string;
var
  mToken: TPascalToken;
  mAssigned, mCounted: string;
begin
  Result := '';
  mToken := ATokens[AIndex];
  mAssigned := AssignedName(ATokens, AIndex);
  mCounted := IncDecName(ATokens, AIndex);
  if mToken.Kind = TPascalTokenKind.Comment then
  begin
    Exit;
  end;
  if MatchText(mToken.Text, ['Break', 'Exit']) and (mToken.Kind = TPascalTokenKind.Identifier) then
  begin
    Result := mToken.Text + cTexts[TTaskCommandsText.IsNotPossibleInTParallel].Text;
  end
  else if mToken.IsKeyword('var') and (AIndex < High(ATokens)) then
  begin
    // Inline-Variablen im Rumpf sind lokal.
    ALocals := ALocals + [ATokens[AIndex + 1].Text];
  end
  else if (mAssigned <> '') and (IndexText(mAssigned, ALocals) < 0) and not SameText(mAssigned, 'Result') then
  begin
    Result := OuterWriteProblem(mAssigned);
  end
  else if (mCounted <> '') and not FollowedByDot(ATokens, AIndex + 2) and (IndexText(mCounted, ALocals) < 0) then
  begin
    Result := OuterWriteProblem(mCounted);
  end;
end;

/// <summary>Grund, warum der Rumpf nicht parallel laufen darf; '' wenn er darf.</summary>
function ParallelProblem(ASource: TCommandSource; ATypes: TDeclaredTypes; const ALoopVar: string;
  AFirst, ALast: Integer): string;
var
  mTokens: TTokens;
  mIndex: Integer;
  mLocals: TArray<string>;
begin
  Result := VclProblem(ASource, ATypes, AFirst, ALast);
  mTokens := TPascalLexer.Tokenize(LinesText(ASource, AFirst, ALast));
  mLocals := [ALoopVar];
  mIndex := 0;
  while (Result = '') and (mIndex <= High(mTokens)) do
  begin
    Result := TokenProblem(mTokens, mIndex, mLocals);
    Inc(mIndex);
  end;
end;


type
  /// <summary>Schleife unter /parallel: for-Knoten, Start- und Endausdruck, Zeilen des Rumpfs.</summary>
  TParallelLoop = record
    ForNode: TSyntaxNode;
    Expressions: TArray<TSyntaxNode>;
    First, Last: Integer;
  end;

/// <summary>Ausdrücke des for-Knotens ohne Typangabe der Inline-Variablen und ohne den Rumpf.</summary>
function ForExpressions(AForNode: TSyntaxNode): TArray<TSyntaxNode>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to AForNode.ChildCount - 2 do
  begin
    if AForNode[mIndex].Kind <> TSyntaxKind.TypeReference then
    begin
      Result := Result + [AForNode[mIndex]];
    end;
  end;
end;

/// <summary>Grund, warum ALoop.ForNode keine aufwärts zählende for-Schleife ist; '' wenn sie es ist. Füllt
/// ALoop.Expressions.</summary>
function ForIssue(ASource: TCommandSource; var ALoop: TParallelLoop): string;
begin
  Result := cTexts[TTaskCommandsText.BelowParallelThereIsNo].Text;
  if (ALoop.ForNode = nil) or (ALoop.ForNode.ChildCount < 3) then
  begin
    Exit;
  end;
  if ContainsText(ASource.Lines[ALoop.ForNode.StartPos.Line], ' downto ') then
  begin
    Exit(cTexts[TTaskCommandsText.TParallelForOnlyCountsUpwards].Text);
  end;
  ALoop.Expressions := ForExpressions(ALoop.ForNode);
  if Length(ALoop.Expressions) = 2 then
  begin
    Result := '';
  end;
end;

/// <summary>Grund, warum der Rumpf von ALoop nicht parallel laufen kann; '' wenn er kann. Füllt First und
/// Last.</summary>
function BodyIssue(ASource: TCommandSource; var ALoop: TParallelLoop): string;
var
  mBody: TSyntaxNode;
  mTypes: TDeclaredTypes;
begin
  mBody := ALoop.ForNode[ALoop.ForNode.ChildCount - 1];
  ALoop.First := mBody.StartPos.Line;
  ALoop.Last := mBody.EndPos.Line;
  if mBody.Kind = TSyntaxKind.Block then
  begin
    Inc(ALoop.First);
    Dec(ALoop.Last);
  end;
  if (ALoop.First > ALoop.Last) or (ALoop.First = ALoop.ForNode.StartPos.Line) then
  begin
    Exit(cTexts[TTaskCommandsText.PleasePutTheBodyOf].Text);
  end;
  mTypes := TDeclaredTypes.Create(ASource.Tree, ASource.Text);
  try
    Result := ParallelProblem(ASource, mTypes, ALoop.ForNode.Name, ALoop.First, ALoop.Last);
  finally
    mTypes.Free;
  end;
end;

/// <summary>Sucht die Schleife unter /parallel; Grund, warum sie nicht parallel laufen kann, sonst ''.</summary>
function LoopIssue(ASource: TCommandSource; out ALoop: TParallelLoop): string;
begin
  ALoop := Default(TParallelLoop);
  Result := '';
  if ASource.RoutineAt = nil then
  begin
    Result := cTexts[TTaskCommandsText.ParallelOnlyAppliesInThe].Text;
  end;
  if Result = '' then
  begin
    ALoop.ForNode := FindFor(ASource.Tree.Root, ASource.Line + 1);
    Result := ForIssue(ASource, ALoop);
  end;
  if Result = '' then
  begin
    Result := BodyIssue(ASource, ALoop);
  end;
end;

/// <summary>Kleinste Einrückung der nichtleeren Zeilen AFirst..ALast; MaxInt ohne solche.</summary>
function CommonIndent(ASource: TCommandSource; AFirst, ALast: Integer): Integer;
var
  mLine, mSpaces: Integer;
begin
  Result := MaxInt;
  for mLine := AFirst to ALast do
  begin
    if Trim(ASource.Lines[mLine]) <> '' then
    begin
      mSpaces := Length(ASource.Lines[mLine]) - Length(TrimLeft(ASource.Lines[mLine]));
      if mSpaces < Result then
      begin
        Result := mSpaces;
      end;
    end;
  end;
end;

/// <summary>Neuer Text: TParallel.For mit dem Rumpf, ohne gemeinsame Einrückung unter "begin" der anonymen
/// Methode.</summary>
function ParallelText(ASource: TCommandSource; const ALoop: TParallelLoop): string;
var
  mIndent, mLB: string;
begin
  mIndent := ASource.Indent(ALoop.ForNode.StartPos.Line);
  mLB := ASource.LineBreak;
  Result := mIndent + Format('TParallel.For(%s, %s,', [NodeText(ASource.Lines, ALoop.Expressions[0]),
    NodeText(ASource.Lines, ALoop.Expressions[1])]) + mLB + mIndent + Format('  procedure(%s: Integer)',
    [ALoop.ForNode.Name]) + mLB + mIndent + '  begin' + mLB + IndentedLines(ASource, ALoop.First, ALoop.Last,
    mIndent + '    ', CommonIndent(ASource, ALoop.First, ALoop.Last)) + mIndent + '  end);' + mLB;
end;

function ExecuteParallel(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mLoop: TParallelLoop;
begin
  AEdits := nil;
  mSource := TCommandSource.Create(AContext);
  try
    AReason := LoopIssue(mSource, mLoop);
    Result := AReason = '';
    if Result then
    begin
      AEdits := [TTextEdit.Create(TTextRange.Create(mSource.Line, 0, mLoop.ForNode.EndPos.Line + 1, 0),
        ParallelText(mSource, mLoop))];
      AddUses(mSource, AContext, mSource.Line, ['System.Threading'], AEdits);
    end;
  finally
    mSource.Free;
  end;
end;

{ /future }

/// <summary>Zeilenzahl, um die AEdits den Text vor Zeile ALine verlängern.</summary>
function LinesAddedBefore(const AEdits: TArray<TTextEdit>; ALine: Integer): Integer;
var
  mEdit: TTextEdit;
  mAdded, mIndex: Integer;
begin
  Result := 0;
  for mEdit in AEdits do
  begin
    if mEdit.Range.EndPos.Line <= ALine then
    begin
      mAdded := 0;
      for mIndex := 1 to Length(mEdit.NewText) do
      begin
        if mEdit.NewText[mIndex] = #10 then
        begin
          Inc(mAdded);
        end;
      end;
      Inc(Result, mAdded - (mEdit.Range.EndPos.Line - mEdit.Range.StartPos.Line));
    end;
  end;
end;

function ExecuteFuture(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mName, mTypeName, mHead, mUri, mIndent: string;
  mUseInline: Boolean;
  mStop: Integer;
  mHost: ISlashHost;
  mCursor: TTextPosition;
begin
  AEdits := nil;
  if not SplitDeclaration(AContext.Arguments, ':', mName, mTypeName) then
  begin
    Exit(Fail(cTexts[TTaskCommandsText.ExpectedIsFutureNameType].Text, AReason));
  end;
  mSource := TCommandSource.Create(AContext);
  try
    mUseInline := TLanguageFeatures.IsAvailable(TLanguageFeature.InlineVariable, AContext.DelphiVersion);
    if mUseInline then
    begin
      mHead := Format('var %s := TTask.Future<%s>(', [mName, mTypeName]);
    end
    else
    begin
      mHead := Format('%s := TTask.Future<%s>(', [mName, mTypeName]);
    end;
    // Zeile hinter dem Future, an der Name.Value gebraucht wird; dorthin kommt der Cursor.
    mStop := BlockEnd(mSource, mSource.Line);
    Result := Wrap(mSource, 'future', TWrapFrame.Create([mHead, Format('  function: %s', [mTypeName]), '  begin'],
      ['  end);', ''], '    '), AEdits, AReason);
    if not Result then
    begin
      Exit;
    end;
    // Ohne Inline-Variablen (vor Delphi 10.3) in den var-Abschnitt.
    if not mUseInline then
    begin
      AEdits := AEdits + [AddLocal(mSource, mSource.RoutineAt, TSyntaxKind.VarSection, 'var',
        Format('%s: IFuture<%s>;', [mName, mTypeName]))];
    end;
    AddUses(mSource, AContext, mSource.Line, ['System.Threading'], AEdits);
    mHost := AContext.Host;
    if (mHost <> nil) and (mStop > 0) then
    begin
      // Die leere Zeile am Ende des Futures steht im neuen Text vor der Zeile Stop.
      mIndent := mSource.Indent(mSource.Line);
      mCursor := TTextPosition.Create(mStop - 1 + LinesAddedBefore(AEdits, mStop), Length(mIndent));
      mUri := AContext.Uri;
      AContext.Defer(
        procedure
        begin
          mHost.MoveCursor(mUri, mCursor);
        end);
    end;
  finally
    mSource.Free;
  end;
end;

{ /atomic }

function IsField(ASource: TCommandSource; const AName: string): Boolean;
var
  mSymbol: TIndexSymbol;
begin
  for mSymbol in ASource.UnitIndex.Symbols do
  begin
    if (mSymbol.Kind = TIndexSymbolKind.Field) and SameText(mSymbol.Name, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Liest die Anweisung unter /atomic ohne Semikolon nach AStatement, ihre Einrückung nach AIndent;
/// Grund, wenn dort keine einzeilige Anweisung steht, sonst ''.</summary>
function AtomicIssue(ASource: TCommandSource; out AIndent, AStatement: string): string;
var
  mLine: string;
begin
  AIndent := '';
  AStatement := '';
  if ASource.RoutineAt = nil then
  begin
    Exit(cTexts[TTaskCommandsText.AtomicOnlyAppliesInThe].Text);
  end;
  if ASource.Line + 1 > High(ASource.Lines) then
  begin
    Exit(cTexts[TTaskCommandsText.BelowAtomicThereIsNo].Text);
  end;
  mLine := ASource.Lines[ASource.Line + 1];
  AIndent := Copy(mLine, 1, Length(mLine) - Length(TrimLeft(mLine)));
  AStatement := Trim(mLine);
  Result := '';
  if EndsStr(';', AStatement) then
  begin
    AStatement := Trim(Copy(AStatement, 1, Length(AStatement) - 1));
  end
  else
  begin
    Result := cTexts[TTaskCommandsText.BelowAtomicThereIsNo2].Text;
  end;
end;

/// <summary>TInterlocked-Aufruf für Inc(F), Inc(F, N), Dec(F) oder Dec(F, N); F kommt nach ATarget.</summary>
function IncDecCall(const AStatement: string; out ATarget: string): string;
var
  mInner, mAmount: string;
  mComma: Integer;
begin
  mInner := Copy(AStatement, 5, Length(AStatement) - 5);
  mComma := Pos(',', mInner);
  if mComma = 0 then
  begin
    ATarget := Trim(mInner);
    Exit(Format('TInterlocked.%s(%s);', [IfThen(StartsText('Inc', AStatement), 'Increment', 'Decrement'),
      ATarget]));
  end;
  ATarget := Trim(Copy(mInner, 1, mComma - 1));
  mAmount := Trim(Copy(mInner, mComma + 1, MaxInt));
  if StartsText('Dec', AStatement) then
  begin
    mAmount := '-(' + mAmount + ')';
  end;
  Result := Format('TInterlocked.Add(%s, %s);', [ATarget, mAmount]);
end;

/// <summary>TInterlocked-Aufruf für F := F + N oder F := F - N; F kommt nach ATarget. '' bei anderer Form.</summary>
function AddCall(const AStatement: string; out ATarget: string): string;
var
  mInner, mAmount: string;
  mAssign: Integer;
begin
  Result := '';
  ATarget := '';
  mAssign := Pos(':=', AStatement);
  if mAssign = 0 then
  begin
    Exit;
  end;
  ATarget := Trim(Copy(AStatement, 1, mAssign - 1));
  mInner := Trim(Copy(AStatement, mAssign + 2, MaxInt));
  mAmount := Trim(Copy(mInner, Length(ATarget) + 4, MaxInt));
  if StartsText(ATarget + ' + ', mInner) then
  begin
    Result := Format('TInterlocked.Add(%s, %s);', [ATarget, mAmount]);
  end
  else if StartsText(ATarget + ' - ', mInner) then
  begin
    Result := Format('TInterlocked.Add(%s, -(%s));', [ATarget, mAmount]);
  end;
end;

/// <summary>TInterlocked-Aufruf für AStatement; '' wenn die Form nicht passt. Das Ziel kommt nach ATarget.</summary>
function AtomicCall(const AStatement: string; out ATarget: string): string;
begin
  if (StartsText('Inc(', AStatement) or StartsText('Dec(', AStatement)) and EndsStr(')', AStatement) then
  begin
    Result := IncDecCall(AStatement, ATarget);
  end
  else
  begin
    Result := AddCall(AStatement, ATarget);
  end;
end;

function ExecuteAtomic(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mIndent, mStatement, mTarget, mCall: string;
begin
  AEdits := nil;
  mSource := TCommandSource.Create(AContext);
  try
    AReason := AtomicIssue(mSource, mIndent, mStatement);
    if AReason = '' then
    begin
      mCall := AtomicCall(mStatement, mTarget);
      if mCall = '' then
      begin
        AReason := cTexts[TTaskCommandsText.ExpectedBelowIsIncF].Text;
      end
      else if not IsField(mSource, mTarget) then
      begin
        AReason := cTexts[TTaskCommandsText.IsNotAFieldAtomic].Fmt([mTarget]);
      end;
    end;
    Result := AReason = '';
    if Result then
    begin
      AEdits := [TTextEdit.Create(TTextRange.Create(mSource.Line, 0, mSource.Line + 2, 0), mIndent + mCall +
        mSource.LineBreak)];
      AddUses(mSource, AContext, mSource.Line, ['System.SyncObjs'], AEdits);
    end;
  finally
    mSource.Free;
  end;
end;

function Command(const AName, ASummary, AExample: string; const AExecute: TSlashExecute): TSlashCommand;
begin
  Result.Name := AName;
  Result.Summary := ASummary;
  Result.Example := AExample;
  Result.Execute := AExecute;
end;

procedure RegisterTaskCommands(const ARegister: TSlashRegister);
begin
  ARegister(Command('task', cTexts[TTaskCommandsText.FollowingStatementsInTTaskRun].Text, '/task', ExecuteTask));
  ARegister(Command('parallel', cTexts[TTaskCommandsText.ForLoopBelowAsTParallel].Text, '/parallel', ExecuteParallel));
  ARegister(Command('future', cTexts[TTaskCommandsText.FollowingStatementsAsTTaskFuture].Text,
    cTexts[TTaskCommandsText.FutureSumInteger].Text,
    ExecuteFuture));
  ARegister(Command('atomic', cTexts[TTaskCommandsText.IncDecOnAField].Text, '/atomic', ExecuteAtomic));
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Editing.TaskCommands', cTexts);

end.
