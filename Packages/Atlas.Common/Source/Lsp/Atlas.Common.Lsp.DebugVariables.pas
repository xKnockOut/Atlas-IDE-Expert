unit Atlas.Common.Lsp.DebugVariables;

// Befehl atlas.server.debugVariables (#853): Ausdrücke für das Fenster
// „Variablen“ beim Debug-Halt, aus dem Syntaxbaum.
//   - autos: Variablen, Felder und einfache Ausdrücke (Bezeichner, Punktketten,
//     Indizes, ^) der Anweisung in der Zeile des Halts, danach die der zuletzt
//     ausgeführten Anweisung (APreviousLine, nur in derselben Routine). Von
//     einer Steueranweisung zählt nur ihr Kopf (Bedingung, Grenzen,
//     Selektor), nicht ihr Rumpf. Ausdrücke mit Aufruf bleiben weg: bei einer
//     Kette die längste Kette ohne Aufruf davor, bei einem Aufruf seine
//     Argumente und das Objekt vor dem Punkt. Aufrufe mit Klammern erkennt die
//     Unit selbst, Getter und Aufrufe ohne Klammern meldet ACallsAt
//     (Namensauflösung über Atlas.Common.Lsp.StepTargets). AIsValue sagt, ob
//     der Bezeichner am Anfang eines Ausdrucks einen Wert hat (Variable, Feld,
//     Parameter); Typen, Konstanten und Unit-Namen bleiben so weg.
//   - locals: Self (in Methoden), Parameter, Result, lokale Variablen der
//     innersten benannten Routine, dazu Inline- und Schleifenvariablen, deren
//     Gültigkeit die Zeile des Halts umfasst. Reihenfolge wie im Quelltext.
// Argumente: [uri, line, previousLine] (Zeilen ab 0, previousLine -1 ohne).
// Antwort: {"format": 1, "autos": ["Betrag", "S"], "locals": ["Self", "S", "Betrag"]}

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Lsp.EnclosingConditions;

type
  /// <summary>Hat der Bezeichner an APosition einen Wert (Variable, Feld, Parameter)?</summary>
  TLspIsValueAt = reference to function(const APosition: TTextPosition): Boolean;

  TLspDebugVariables = class
  public const
    cCommand = 'atlas.server.debugVariables';
    /// <summary>Längere Ausdrücke zeigt „Autos“ nicht.</summary>
    cMaxText = 100;
    cMaxAutos = 50;
  private
    FTree: TSyntaxTree;
    FText: string;
    FCallsAt: TLspCallsAt;
    FIsValue: TLspIsValueAt;
    FCalls: TArray<TTextPosition>;
    FFound: TList<string>;
    FSeen: TDictionary<string, Boolean>;
    function TextOf(ANode: TSyntaxNode): string;
    function HasCall(ANode: TSyntaxNode): Boolean;
    function RootIsValue(ANode: TSyntaxNode): Boolean;
    procedure Add(const AText: string);
    function TryAddChain(ANode: TSyntaxNode): Boolean;
    procedure CollectCall(ANode: TSyntaxNode);
    procedure Collect(ANode: TSyntaxNode);
    procedure CollectStatement(AStatement: TSyntaxNode);
    function Path(ALine: Integer): TArray<TSyntaxNode>;
    function StatementAt(ALine: Integer; out ARoutine: TSyntaxNode): TSyntaxNode;
    procedure AddLocalsOf(ARoutine: TSyntaxNode);
    procedure AddScopedLocals(ARoutine: TSyntaxNode; ALine: Integer);
    procedure Reset;
  public
    /// <summary>ACallsAt und AIsValue dürfen nil sein: Dann zählen nur Aufrufe mit Klammern, und jeder Bezeichner
    /// gilt als Wert.</summary>
    constructor Create(ATree: TSyntaxTree; const AText: string; const ACallsAt: TLspCallsAt;
      const AIsValue: TLspIsValueAt);
    destructor Destroy; override;
    /// <summary>Ausdrücke für „Autos“ beim Halt in ALine nach APreviousLine (-1 ohne), höchstens MaxAutos.</summary>
    function Autos(ALine, APreviousLine: Integer): TArray<string>;
    /// <summary>Lokale Variablen und Parameter der Routine mit ALine.</summary>
    function Locals(ALine: Integer): TArray<string>;
    /// <summary>Der Befehl: Antwort als JSON (format 1).</summary>
    function Execute(ALine, APreviousLine: Integer): TJSONObject;
    class function ToJson(const AAutos, ALocals: TArray<string>): TJSONObject; static;
  end;

implementation

uses
  System.StrUtils;

const
  cStatementKinds = [TSyntaxKind.AssignStatement, TSyntaxKind.CallStatement, TSyntaxKind.IfStatement,
    TSyntaxKind.CaseStatement, TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement,
    TSyntaxKind.RepeatStatement, TSyntaxKind.WithStatement, TSyntaxKind.RaiseStatement, TSyntaxKind.InlineVar,
    TSyntaxKind.InlineConst];
  cExpressionKinds = [TSyntaxKind.Identifier, TSyntaxKind.Literal, TSyntaxKind.MemberAccess, TSyntaxKind.Call,
    TSyntaxKind.IndexAccess, TSyntaxKind.Dereference, TSyntaxKind.AddressOf, TSyntaxKind.SetConstructor,
    TSyntaxKind.BinaryExpr, TSyntaxKind.UnaryExpr, TSyntaxKind.ParenExpr, TSyntaxKind.RangeExpr,
    TSyntaxKind.IfExpr];
  cChainKinds = [TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess, TSyntaxKind.Dereference];
  // Bezeichner ohne Wert für den Debugger.
  cNoValueWords: array[0..3] of string = ('nil', 'true', 'false', 'inherited');

function Contains(ANode: TSyntaxNode; ALine: Integer): Boolean;
begin
  Result := (ANode.StartPos.Line <= ALine) and (ALine <= ANode.EndPos.Line);
end;

function Before(const A, B: TTextPosition): Boolean;
begin
  Result := (A.Line < B.Line) or ((A.Line = B.Line) and (A.Character < B.Character));
end;

/// <summary>Namen einer Deklaration „A,B“ einzeln.</summary>
function NamesOf(ANode: TSyntaxNode): TArray<string>;
var
  mName: string;
begin
  Result := nil;
  for mName in ANode.Name.Split([',']) do
  begin
    if Trim(mName) <> '' then
    begin
      Result := Result + [Trim(mName)];
    end;
  end;
end;

function IsNoValueWord(const AText: string): Boolean;
var
  mWord: string;
begin
  Result := False;
  for mWord in cNoValueWords do
  begin
    if SameText(mWord, AText) then
    begin
      Exit(True);
    end;
  end;
end;

{ TLspDebugVariables }

constructor TLspDebugVariables.Create(ATree: TSyntaxTree; const AText: string; const ACallsAt: TLspCallsAt;
  const AIsValue: TLspIsValueAt);
begin
  inherited Create;
  FTree := ATree;
  FText := AText;
  FCallsAt := ACallsAt;
  FIsValue := AIsValue;
  FFound := TList<string>.Create;
  FSeen := TDictionary<string, Boolean>.Create;
end;

destructor TLspDebugVariables.Destroy;
begin
  FreeAndNil(FSeen);
  FreeAndNil(FFound);
  inherited Destroy;
end;

procedure TLspDebugVariables.Reset;
begin
  FFound.Clear;
  FSeen.Clear;
  FCalls := nil;
end;

function TLspDebugVariables.TextOf(ANode: TSyntaxNode): string;
begin
  Result := '';
  if (ANode = nil) or (ANode.EndOffset <= ANode.StartOffset) or (ANode.EndOffset > Length(FText)) then
  begin
    Exit;
  end;
  Result := Copy(FText, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
  // Mehrzeilig bzw. mit Leerraum: in eine Zeile, ohne Leerzeichen um Punkte und Klammern.
  Result := Result.Replace(#13, ' ').Replace(#10, ' ').Replace(#9, ' ');
  while Pos('  ', Result) > 0 do
  begin
    Result := Result.Replace('  ', ' ');
  end;
  Result := Trim(Result.Replace(' .', '.').Replace('. ', '.').Replace(' [', '[').Replace('[ ', '[')
    .Replace(' ]', ']').Replace(' ^', '^'));
end;

function TLspDebugVariables.HasCall(ANode: TSyntaxNode): Boolean;
var
  mPosition: TTextPosition;
  mFound: TSyntaxNode;
begin
  // Aufrufe mit Klammern und anonyme Methoden sieht der Baum selbst.
  mFound := ANode.Search(
    function(ANext: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if ANext.Kind in [TSyntaxKind.Call, TSyntaxKind.AnonymousMethod, TSyntaxKind.GenericArgs,
        TSyntaxKind.InheritedExpr] then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end);
  Result := mFound <> nil;
  if Result then
  begin
    Exit;
  end;
  // Getter und Aufrufe ohne Klammern: aus der Namensauflösung.
  for mPosition in FCalls do
  begin
    if not Before(mPosition, ANode.StartPos) and Before(mPosition, ANode.EndPos) then
    begin
      Exit(True);
    end;
  end;
end;

function TLspDebugVariables.RootIsValue(ANode: TSyntaxNode): Boolean;
var
  mRoot: TSyntaxNode;
begin
  mRoot := ANode;
  while (mRoot.Kind in cChainKinds) and (mRoot.ChildCount > 0) do
  begin
    mRoot := mRoot.Children[0];
  end;
  Result := (mRoot.Kind = TSyntaxKind.Identifier) and (mRoot.Name <> '') and not IsNoValueWord(mRoot.Name);
  if Result and not SameText(mRoot.Name, 'Self') and Assigned(FIsValue) then
  begin
    Result := FIsValue(mRoot.StartPos);
  end;
end;

procedure TLspDebugVariables.Add(const AText: string);
var
  mKey: string;
begin
  mKey := LowerCase(AText.Replace(' ', ''));
  if (AText = '') or (Length(AText) > cMaxText) or FSeen.ContainsKey(mKey) or (FFound.Count >= cMaxAutos) then
  begin
    Exit;
  end;
  FSeen.Add(mKey, True);
  FFound.Add(AText);
end;

function TLspDebugVariables.TryAddChain(ANode: TSyntaxNode): Boolean;
begin
  Result := not HasCall(ANode) and RootIsValue(ANode);
  if Result then
  begin
    Add(TextOf(ANode));
  end;
end;

procedure TLspDebugVariables.CollectCall(ANode: TSyntaxNode);
var
  mIndex: Integer;
  mCallee: TSyntaxNode;
begin
  // Obj.Methode(X): Obj und X, nicht den Aufruf. F(X), Integer(X): nur X.
  mCallee := ANode.Children[0];
  if (mCallee.Kind in cChainKinds) and (mCallee.ChildCount > 0) then
  begin
    Collect(mCallee.Children[0]);
    for mIndex := 1 to mCallee.ChildCount - 1 do
    begin
      Collect(mCallee.Children[mIndex]);
    end;
  end;
  for mIndex := 1 to ANode.ChildCount - 1 do
  begin
    Collect(ANode.Children[mIndex]);
  end;
end;

procedure TLspDebugVariables.Collect(ANode: TSyntaxNode);
var
  mIndex: Integer;
begin
  if (ANode = nil) or not (ANode.Kind in cExpressionKinds) then
  begin
    Exit;
  end;
  case ANode.Kind of
    TSyntaxKind.Literal:
      ;
    TSyntaxKind.Identifier:
      TryAddChain(ANode);
    TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess, TSyntaxKind.Dereference:
      begin
        // Längste Kette ohne Aufruf; sonst die Kette davor.
        if not TryAddChain(ANode) and (ANode.ChildCount > 0) then
        begin
          Collect(ANode.Children[0]);
        end;
        // Indizes zählen für sich: Liste[I] zeigt auch I.
        if ANode.Kind = TSyntaxKind.IndexAccess then
        begin
          for mIndex := 1 to ANode.ChildCount - 1 do
          begin
            Collect(ANode.Children[mIndex]);
          end;
        end;
      end;
    TSyntaxKind.Call:
      if ANode.ChildCount > 0 then
      begin
        CollectCall(ANode);
      end;
  else
    for mIndex := 0 to ANode.ChildCount - 1 do
    begin
      Collect(ANode.Children[mIndex]);
    end;
  end;
end;

procedure TLspDebugVariables.CollectStatement(AStatement: TSyntaxNode);
var
  mIndex: Integer;
  mName: string;
begin
  if AStatement = nil then
  begin
    Exit;
  end;
  if Assigned(FCallsAt) then
  begin
    FCalls := FCallsAt(AStatement.StartPos.Line);
  end;
  // Schleifen- und Inline-Variablen tragen ihren Namen am Knoten.
  if AStatement.Kind in [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.InlineVar] then
  begin
    for mName in NamesOf(AStatement) do
    begin
      Add(mName);
    end;
  end;
  // Nur die Ausdrücke der Anweisung selbst: Rümpfe und Zweige sind eigene Anweisungen.
  for mIndex := 0 to AStatement.ChildCount - 1 do
  begin
    Collect(AStatement.Children[mIndex]);
  end;
end;

function TLspDebugVariables.Path(ALine: Integer): TArray<TSyntaxNode>;
var
  mNode, mNext: TSyntaxNode;
  mIndex: Integer;
begin
  Result := nil;
  mNode := FTree.Root;
  while mNode <> nil do
  begin
    Result := Result + [mNode];
    // Reichen mehrere Kinder in die Zeile, gilt das letzte (wie bei „Warum bin ich hier?“).
    mNext := nil;
    for mIndex := mNode.ChildCount - 1 downto 0 do
    begin
      if Contains(mNode.Children[mIndex], ALine) then
      begin
        mNext := mNode.Children[mIndex];
        Break;
      end;
    end;
    mNode := mNext;
  end;
end;

function TLspDebugVariables.StatementAt(ALine: Integer; out ARoutine: TSyntaxNode): TSyntaxNode;
var
  mPath: TArray<TSyntaxNode>;
  mIndex: Integer;
begin
  Result := nil;
  ARoutine := nil;
  if ALine < 0 then
  begin
    Exit;
  end;
  mPath := Path(ALine);
  for mIndex := High(mPath) downto 0 do
  begin
    if (Result = nil) and (mPath[mIndex].Kind in cStatementKinds) then
    begin
      Result := mPath[mIndex];
    end;
    if mPath[mIndex].Kind = TSyntaxKind.RoutineDecl then
    begin
      ARoutine := mPath[mIndex];
      Exit;
    end;
  end;
  // Außerhalb einer Routine (initialization) gibt es keine Autos aus einer Routine.
  Result := nil;
end;

function TLspDebugVariables.Autos(ALine, APreviousLine: Integer): TArray<string>;
var
  mCurrent, mPrevious, mRoutine, mPreviousRoutine: TSyntaxNode;
begin
  Reset;
  mCurrent := StatementAt(ALine, mRoutine);
  CollectStatement(mCurrent);
  if APreviousLine <> ALine then
  begin
    mPrevious := StatementAt(APreviousLine, mPreviousRoutine);
    // Die vorige Anweisung nur aus derselben Routine: Nach einem Rücksprung sind ihre Variablen weg.
    if (mPrevious <> nil) and (mPrevious <> mCurrent) and (mRoutine <> nil) and (mPreviousRoutine = mRoutine) then
    begin
      CollectStatement(mPrevious);
    end;
  end;
  Result := FFound.ToArray;
end;

procedure TLspDebugVariables.AddLocalsOf(ARoutine: TSyntaxNode);
var
  mHeader, mParams, mChild: TSyntaxNode;
  mIndex, mDecl: Integer;
  mName: string;
begin
  mHeader := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
  // Methoden „TKlasse.Name“ haben Self.
  if ContainsStr(ARoutine.Name, '.') then
  begin
    Add('Self');
  end;
  if mHeader <> nil then
  begin
    mParams := mHeader.FindChild(TSyntaxKind.Parameters);
    if mParams <> nil then
    begin
      for mIndex := 0 to mParams.ChildCount - 1 do
      begin
        for mName in NamesOf(mParams.Children[mIndex]) do
        begin
          Add(mName);
        end;
      end;
    end;
    // Ergebnistyp direkt am Kopf: Funktion bzw. Operator.
    if mHeader.FindChild(TSyntaxKind.TypeReference) <> nil then
    begin
      Add('Result');
    end;
  end;
  for mIndex := 0 to ARoutine.ChildCount - 1 do
  begin
    mChild := ARoutine.Children[mIndex];
    if mChild.Kind <> TSyntaxKind.VarSection then
    begin
      Continue;
    end;
    for mDecl := 0 to mChild.ChildCount - 1 do
    begin
      if mChild.Children[mDecl].Kind = TSyntaxKind.VarDecl then
      begin
        for mName in NamesOf(mChild.Children[mDecl]) do
        begin
          Add(mName);
        end;
      end;
    end;
  end;
end;

procedure TLspDebugVariables.AddScopedLocals(ARoutine: TSyntaxNode; ALine: Integer);
var
  mBlock: TSyntaxNode;
begin
  mBlock := ARoutine.FindChild(TSyntaxKind.Block);
  if mBlock = nil then
  begin
    Exit;
  end;
  mBlock.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      mName: string;
      mScoped: Boolean;
    begin
      // Verschachtelte Routinen und anonyme Methoden haben eigene Variablen.
      Result := not (ANode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod]);
      // Inline-Variable: gültig ab ihrer Zeile bis zum Ende ihres Blocks; Schleifenvariable: in der Schleife.
      mScoped := ((ANode.Kind = TSyntaxKind.InlineVar) and (ANode.StartPos.Line < ALine) and
        (ANode.Parent <> nil) and Contains(ANode.Parent, ALine)) or
        ((ANode.Kind in [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement]) and Contains(ANode, ALine));
      if mScoped then
      begin
        for mName in NamesOf(ANode) do
        begin
          Add(mName);
        end;
      end;
    end);
end;

function TLspDebugVariables.Locals(ALine: Integer): TArray<string>;
var
  mRoutine: TSyntaxNode;
begin
  Reset;
  StatementAt(ALine, mRoutine);
  if mRoutine = nil then
  begin
    Exit(nil);
  end;
  AddLocalsOf(mRoutine);
  AddScopedLocals(mRoutine, ALine);
  Result := FFound.ToArray;
end;

function TLspDebugVariables.Execute(ALine, APreviousLine: Integer): TJSONObject;
var
  mAutos: TArray<string>;
begin
  mAutos := Autos(ALine, APreviousLine);
  Result := ToJson(mAutos, Locals(ALine));
end;

function StringsToJson(const AItems: TArray<string>): TJSONArray;
var
  mItem: string;
begin
  Result := TJSONArray.Create;
  for mItem in AItems do
  begin
    Result.Add(mItem);
  end;
end;

class function TLspDebugVariables.ToJson(const AAutos, ALocals: TArray<string>): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('format', TJSONNumber.Create(1));
  Result.AddPair('autos', StringsToJson(AAutos));
  Result.AddPair('locals', StringsToJson(ALocals));
end;

end.
