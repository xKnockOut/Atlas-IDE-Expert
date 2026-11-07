unit Atlas.Common.Pascal.SyntaxChecks;

// Syntaxprüfungen am fertigen Baum wie beim Compiler (#1022), für Fälle, die
// der fehlertolerante Parser durchlässt:
//   E2023  function ohne Ergebnistyp an einer Deklaration
//   E2025  procedure mit Ergebnistyp
//   E2031  goto auf eine nicht deklarierte Marke
//   E2049  label im interface-Teil
//   E2058  Klassen-, Interface- oder object-Typ außerhalb des type-Abschnitts
//          (var X: class … end), in einer Routine dazu E2059
//   E2059  lokaler Klassen-, Interface- oder object-Typ in einer Routine
//          (Delphi 13 meldet nicht mehr E2060 und E2061, #1382)
//   E2123  class operator in einer Klasse, einem Interface oder object-Typ
//          (Operatoren gibt es nur in Records, #1382)
//   E2067  Wertparameter ohne Typ
//   E2195  lokale Variable mit Anfangswert im var-Abschnitt
//   E2196  mehrere Variablen mit einem Anfangswert
// Gemeldet wird nur, was am Baum sicher ist: Eine Implementierung ohne
// Ergebnistyp ist erlaubt, wenn die Datei die Routine mit Ergebnistyp
// deklariert; Methoden (Name mit Punkt) sind in ihrer Klasse deklariert.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree;

type
  TSyntaxChecks = record
  public
    /// <summary>Befunde zu ARoot; ATokens sind alle Token der Datei (auch Kommentare), sortiert. Inaktive
    /// Zweige der bedingten Übersetzung stehen nicht im Baum und bleiben so still.</summary>
    class function Check(ARoot: TSyntaxNode; const ATokens: TArray<TPascalToken>): TArray<TSyntaxDiagnostic>;
      static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TSyntaxChecksText = (AProcedureCannotHaveA, TheFunctionNeedsAResult, ParameterTypeMissingFor,
    SeveralVariablesCannotBeInitialized, LocalVariablesCannotBeInitialized, ClassInterfaceAndObjectTypes,
    LocalClassInterfaceAndObject, ProcedureFunctionPropertyOrVar, LabelExpectedIsNotDeclared,
    LabelDeclarationsAreNotAllowed, Like);

const
  cTexts: array[TSyntaxChecksText] of TAtlasText = (
    (De: 'Eine Prozedur kann keinen Ergebnistyp haben'; En: 'A procedure cannot have a result type'),
    (De: 'Die Funktion %s braucht einen Ergebnistyp'; En: 'The function %s needs a result type'),
    (De: 'Parametertyp fehlt bei %s'; En: 'Parameter type missing for %s'),
    (De: 'Mehrere Variablen lassen sich nicht gemeinsam initialisieren';
     En: 'Several variables cannot be initialized together'),
    (De: 'Lokale Variablen lassen sich im var-Abschnitt nicht initialisieren';
     En: 'Local variables cannot be initialized in the var section'),
    (De: 'Klassen-, Interface- und Objekttypen sind nur im type-Abschnitt erlaubt';
     En: 'Class, interface and object types are only allowed in the type section'),
    (De: 'Lokale Klassen-, Interface- und Objekttypen sind nicht erlaubt';
     En: 'Local class, interface and object types are not allowed'),
    (De: '''procedure'', ''function'', ''property'' oder ''var'' erwartet, aber ''%s'' gefunden';
     En: '''procedure'', ''function'', ''property'' or ''var'' expected but ''%s'' found'),
    (De: 'Marke erwartet: %s ist nicht als label deklariert'; En: 'Label expected: %s is not declared as label'),
    (De: 'Label-Deklarationen sind im interface-Teil nicht erlaubt';
     En: 'Label declarations are not allowed in the interface part'),
    (De: ' (wie %s).'; En: ' (like %s).'));

{$SCOPEDENUMS OFF}

type
  TTreeChecker = class
  private
    FTokens: TArray<TPascalToken>;
    FByOffset: TDictionary<Integer, Integer>;
    FResult: TList<TSyntaxDiagnostic>;
    // Namen von Routinenköpfen mit Ergebnistyp (klein): Deklarationen, zu denen eine Implementierung ohne
    // Ergebnistyp gehören darf.
    FWithResult: TDictionary<string, Boolean>;
    procedure Add(const ACode, AMessage: string; const AStartPos, AEndPos: TTextPosition);
    function IndexAt(AOffset: Integer): Integer;
    /// <summary>Erstes Token, das bei AOffset oder dahinter beginnt; Length(FTokens) ohne.</summary>
    function IndexFrom(AOffset: Integer): Integer;
    function NextCode(AIndex: Integer): Integer;
    /// <summary>Erstes Token mit Symbol ASymbol in [AFrom, ATo) (Offsets), -1 ohne.</summary>
    function SymbolBetween(const ASymbol: string; AFrom, ATo: Integer): Integer;
    function WordBetween(const AWord: string; AFrom, ATo: Integer): Boolean;
    function HeaderWord(AHeader: TSyntaxNode): string;
    function ResultTypeOf(AHeader: TSyntaxNode): TSyntaxNode;
    function InRoutine(ANode: TSyntaxNode): Boolean;
    procedure CollectDeclared(ARoot: TSyntaxNode);
    procedure CheckHeader(AHeader: TSyntaxNode);
    procedure CheckParameter(AParameter: TSyntaxNode);
    procedure CheckVarDecl(ADecl: TSyntaxNode);
    procedure CheckFieldType(ADecl: TSyntaxNode);
    procedure CheckTypeDecl(ADecl: TSyntaxNode);
    procedure CheckClassOperator(AHeader: TSyntaxNode);
    procedure CheckGoto(AGoto: TSyntaxNode);
    function LabelsOf(AScope: TSyntaxNode): TArray<string>;
    /// <summary>Knoten, deren Kinder Marken-Abschnitte von AScope sein können.</summary>
    function LabelContainers(AScope: TSyntaxNode): TArray<TSyntaxNode>;
    /// <summary>Hängt die Marken des Abschnitts ASection an AResult an.</summary>
    procedure AddSectionLabels(ASection: TSyntaxNode; var AResult: TArray<string>);
    /// <summary>Routine oder Datei, in der AGoto steht; nil in anonymen Methoden.</summary>
    function GotoScope(AGoto: TSyntaxNode): TSyntaxNode;
    /// <summary>Ist die Marke AKey in AScope oder einer umgebenden Routine deklariert?</summary>
    function LabelVisible(AScope: TSyntaxNode; const AKey: string): Boolean;
  public
    constructor Create(const ATokens: TArray<TPascalToken>);
    destructor Destroy; override;
    function Run(ARoot: TSyntaxNode): TArray<TSyntaxDiagnostic>;
  end;

const
  cTypeKinds: set of TSyntaxKind = [TSyntaxKind.ClassType, TSyntaxKind.ObjectType, TSyntaxKind.RecordType,
    TSyntaxKind.InterfaceType, TSyntaxKind.HelperType];
  cClassLikeKinds: set of TSyntaxKind = [TSyntaxKind.ClassType, TSyntaxKind.ObjectType, TSyntaxKind.InterfaceType,
    TSyntaxKind.ForwardType];
  cHeaderParts: set of TSyntaxKind = [TSyntaxKind.Parameters, TSyntaxKind.GenericParams, TSyntaxKind.Directive,
    TSyntaxKind.Attribute];

/// <summary>Marke vergleichbar machen: Zahlen ohne führende Nullen, Namen klein.</summary>
function LabelKey(const AText: string): string;
var
  mNumber: Int64;
begin
  if TryStrToInt64(AText, mNumber) then
  begin
    Result := IntToStr(mNumber);
  end
  else
  begin
    Result := LowerCase(AText);
  end;
end;

{ TTreeChecker }

constructor TTreeChecker.Create(const ATokens: TArray<TPascalToken>);
var
  mIndex: Integer;
begin
  inherited Create;
  FTokens := ATokens;
  FByOffset := TDictionary<Integer, Integer>.Create;
  for mIndex := 0 to High(FTokens) do
  begin
    FByOffset.AddOrSetValue(FTokens[mIndex].Offset, mIndex);
  end;
  FResult := TList<TSyntaxDiagnostic>.Create;
  FWithResult := TDictionary<string, Boolean>.Create;
end;

destructor TTreeChecker.Destroy;
begin
  FWithResult.Free;
  FResult.Free;
  FByOffset.Free;
  inherited;
end;

procedure TTreeChecker.Add(const ACode, AMessage: string; const AStartPos, AEndPos: TTextPosition);
var
  mDiagnostic: TSyntaxDiagnostic;
begin
  mDiagnostic := Default(TSyntaxDiagnostic);
  mDiagnostic.Message := AMessage + cTexts[TSyntaxChecksText.Like].Fmt([ACode]);
  mDiagnostic.StartPos := AStartPos;
  mDiagnostic.EndPos := AEndPos;
  mDiagnostic.Code := ACode;
  mDiagnostic.TreeIntact := True;
  FResult.Add(mDiagnostic);
end;

function TTreeChecker.IndexAt(AOffset: Integer): Integer;
begin
  if not FByOffset.TryGetValue(AOffset, Result) then
  begin
    Result := -1;
  end;
end;

function TTreeChecker.IndexFrom(AOffset: Integer): Integer;
var
  mLower, mUpper, mMiddle: Integer;
begin
  mLower := 0;
  mUpper := Length(FTokens);
  while mLower < mUpper do
  begin
    mMiddle := (mLower + mUpper) div 2;
    if FTokens[mMiddle].Offset < AOffset then
    begin
      mLower := mMiddle + 1;
    end
    else
    begin
      mUpper := mMiddle;
    end;
  end;
  Result := mLower;
end;

function TTreeChecker.NextCode(AIndex: Integer): Integer;
begin
  Result := AIndex + 1;
  while (Result <= High(FTokens)) and (FTokens[Result].Kind in [TPascalTokenKind.Comment,
    TPascalTokenKind.Directive]) do
  begin
    Inc(Result);
  end;
  if Result > High(FTokens) then
  begin
    Result := -1;
  end;
end;

function TTreeChecker.SymbolBetween(const ASymbol: string; AFrom, ATo: Integer): Integer;
var
  mIndex: Integer;
begin
  mIndex := IndexFrom(AFrom);
  while (mIndex <= High(FTokens)) and (FTokens[mIndex].Offset < ATo) do
  begin
    if FTokens[mIndex].IsSymbol(ASymbol) then
    begin
      Exit(mIndex);
    end;
    Inc(mIndex);
  end;
  Result := -1;
end;

function TTreeChecker.WordBetween(const AWord: string; AFrom, ATo: Integer): Boolean;
var
  mIndex: Integer;
begin
  mIndex := IndexFrom(AFrom);
  while (mIndex <= High(FTokens)) and (FTokens[mIndex].Offset < ATo) do
  begin
    if (FTokens[mIndex].Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) and
      SameText(FTokens[mIndex].Text, AWord) then
    begin
      Exit(True);
    end;
    Inc(mIndex);
  end;
  Result := False;
end;

function TTreeChecker.HeaderWord(AHeader: TSyntaxNode): string;
var
  mIndex: Integer;
begin
  Result := '';
  mIndex := IndexAt(AHeader.StartOffset);
  if mIndex < 0 then
  begin
    Exit;
  end;
  if FTokens[mIndex].IsKeyword('class') then
  begin
    mIndex := NextCode(mIndex);
  end;
  if mIndex >= 0 then
  begin
    Result := LowerCase(FTokens[mIndex].Text);
  end;
end;

function TTreeChecker.ResultTypeOf(AHeader: TSyntaxNode): TSyntaxNode;
var
  mIndex: Integer;
begin
  // Kinder des Kopfs: Typparameter, Parameter, Direktiven, Attribute und der Ergebnistyp.
  for mIndex := 0 to AHeader.ChildCount - 1 do
  begin
    if not (AHeader[mIndex].Kind in cHeaderParts) then
    begin
      Exit(AHeader[mIndex]);
    end;
  end;
  Result := nil;
end;

function TTreeChecker.InRoutine(ANode: TSyntaxNode): Boolean;
var
  mNode: TSyntaxNode;
begin
  mNode := ANode.Parent;
  while mNode <> nil do
  begin
    if mNode.Kind = TSyntaxKind.RoutineDecl then
    begin
      Exit(True);
    end;
    mNode := mNode.Parent;
  end;
  Result := False;
end;

procedure TTreeChecker.CollectDeclared(ARoot: TSyntaxNode);
begin
  ARoot.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := True;
      if (ANode.Kind = TSyntaxKind.RoutineHeader) and (ResultTypeOf(ANode) <> nil) then
      begin
        FWithResult.AddOrSetValue(LowerCase(ANode.Name), True);
      end;
    end);
end;

procedure TTreeChecker.CheckHeader(AHeader: TSyntaxNode);
var
  mWord: string;
  mResultType, mOwner: TSyntaxNode;
  mDeclaration: Boolean;
begin
  mOwner := AHeader.Parent;
  if (mOwner = nil) or (AHeader.Name = '') then
  begin
    Exit;
  end;
  mWord := HeaderWord(AHeader);
  mResultType := ResultTypeOf(AHeader);
  if (mWord = 'procedure') and (mResultType <> nil) then
  begin
    Add('E2025', cTexts[TSyntaxChecksText.AProcedureCannotHaveA].Text, mResultType.StartPos, mResultType.EndPos);
    Exit;
  end;
  // Eine Methodenzuordnung (function IFoo.GetX = MyGetX) hat nie einen Ergebnistyp (#1134).
  if (mWord <> 'function') or (mResultType <> nil) or AHeader.IsMethodResolution then
  begin
    Exit;
  end;
  // Deklaration: in einem Typ, im interface-Teil, forward/external oder eine freie Routine ohne
  // Deklaration mit Ergebnistyp in der Datei.
  if mOwner.Kind in cTypeKinds then
  begin
    mDeclaration := True;
  end
  else if mOwner.Kind = TSyntaxKind.RoutineDecl then
  begin
    mDeclaration := ((mOwner.Parent <> nil) and (mOwner.Parent.Kind = TSyntaxKind.InterfaceSection)) or
      ((Pos('.', AHeader.Name) = 0) and not FWithResult.ContainsKey(LowerCase(AHeader.Name)));
  end
  else
  begin
    mDeclaration := False;
  end;
  if mDeclaration then
  begin
    Add('E2023', cTexts[TSyntaxChecksText.TheFunctionNeedsAResult].Fmt([AHeader.Name]), AHeader.StartPos,
      AHeader.EndPos);
  end;
end;

procedure TTreeChecker.CheckParameter(AParameter: TSyntaxNode);
begin
  // procedure Foo(A); – nur const, var, out und constref dürfen ohne Typ stehen.
  if (AParameter.Name = '') or (AParameter.Modifier <> TParameterModifier.None) or
    (SymbolBetween(':', AParameter.StartOffset, AParameter.EndOffset) >= 0) then
  begin
    Exit;
  end;
  Add('E2067', cTexts[TSyntaxChecksText.ParameterTypeMissingFor].Fmt([StringReplace(AParameter.Name, ',', ', ',
    [rfReplaceAll])]),
    AParameter.StartPos, AParameter.EndPos);
end;

procedure TTreeChecker.CheckVarDecl(ADecl: TSyntaxNode);
var
  mSection, mOwner: TSyntaxNode;
  mEqual: Integer;
  mLocal: Boolean;
begin
  CheckFieldType(ADecl);
  mSection := ADecl.Parent;
  if (mSection = nil) or (mSection.Kind <> TSyntaxKind.VarSection) or (mSection.Parent = nil) or
    (ADecl.ChildCount < 2) then
  begin
    Exit;
  end;
  mOwner := mSection.Parent;
  if mOwner.Kind = TSyntaxKind.RoutineDecl then
  begin
    mLocal := True;
  end
  else if mOwner.Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection, TSyntaxKind.ProgramFile,
    TSyntaxKind.LibraryFile, TSyntaxKind.PackageFile] then
  begin
    mLocal := False;
  end
  else
  begin
    Exit;
  end;
  // X: Typ = Wert: das "=" zwischen Typ und Ausdruck; absolute hat keins.
  mEqual := SymbolBetween('=', ADecl[0].EndOffset, ADecl[1].StartOffset);
  if (mEqual < 0) or WordBetween('absolute', ADecl[0].EndOffset, ADecl[1].StartOffset) then
  begin
    Exit;
  end;
  if Pos(',', ADecl.Name) > 0 then
  begin
    Add('E2196', cTexts[TSyntaxChecksText.SeveralVariablesCannotBeInitialized].Text, FTokens[mEqual].StartPos,
      FTokens[mEqual].EndPos);
  end
  else if mLocal then
  begin
    Add('E2195', cTexts[TSyntaxChecksText.LocalVariablesCannotBeInitialized].Text, FTokens[mEqual].StartPos,
      FTokens[mEqual].EndPos);
  end;
end;

procedure TTreeChecker.CheckFieldType(ADecl: TSyntaxNode);
var
  mTypeNode: TSyntaxNode;
begin
  // var X: class … end; – Klassen, Interfaces und Objekte brauchen einen Namen aus dem type-Abschnitt.
  if ADecl.ChildCount = 0 then
  begin
    Exit;
  end;
  mTypeNode := ADecl[0];
  if not (mTypeNode.Kind in [TSyntaxKind.ObjectType, TSyntaxKind.ClassType, TSyntaxKind.InterfaceType]) then
  begin
    Exit;
  end;
  // Delphi 13 meldet für alle drei Arten E2058, in einer Routine zusätzlich E2059 (lokaler Typ). Zwei Meldungen
  // an derselben Stelle fasst der Parser zusammen: E2059 steht deshalb am Namen.
  Add('E2058', cTexts[TSyntaxChecksText.ClassInterfaceAndObjectTypes].Text, mTypeNode.StartPos,
    mTypeNode.EndPos);
  if InRoutine(ADecl) then
  begin
    Add('E2059', cTexts[TSyntaxChecksText.LocalClassInterfaceAndObject].Text, ADecl.StartPos,
      mTypeNode.StartPos);
  end;
end;

procedure TTreeChecker.CheckTypeDecl(ADecl: TSyntaxNode);
var
  mIndex: Integer;
  mTypeNode: TSyntaxNode;
begin
  if not InRoutine(ADecl) then
  begin
    Exit;
  end;
  mTypeNode := nil;
  for mIndex := 0 to ADecl.ChildCount - 1 do
  begin
    if ADecl[mIndex].Kind in cClassLikeKinds then
    begin
      mTypeNode := ADecl[mIndex];
      Break;
    end;
  end;
  if mTypeNode = nil then
  begin
    Exit;
  end;
  Add('E2059', cTexts[TSyntaxChecksText.LocalClassInterfaceAndObject].Text, ADecl.StartPos, ADecl.EndPos);
end;

procedure TTreeChecker.CheckClassOperator(AHeader: TSyntaxNode);
var
  mIndex: Integer;
begin
  if (AHeader.Parent = nil) or not (AHeader.Parent.Kind in [TSyntaxKind.ClassType, TSyntaxKind.ObjectType,
    TSyntaxKind.InterfaceType]) then
  begin
    Exit;
  end;
  mIndex := IndexAt(AHeader.StartOffset);
  if (mIndex < 0) or not FTokens[mIndex].IsKeyword('class') then
  begin
    Exit;
  end;
  mIndex := NextCode(mIndex);
  if (mIndex < 0) or not SameText(FTokens[mIndex].Text, 'operator') then
  begin
    Exit;
  end;
  Add('E2123', cTexts[TSyntaxChecksText.ProcedureFunctionPropertyOrVar].Fmt([FTokens[mIndex].Text]),
    FTokens[mIndex].StartPos, FTokens[mIndex].EndPos);
end;

function TTreeChecker.LabelContainers(AScope: TSyntaxNode): TArray<TSyntaxNode>;
var
  mIndex: Integer;
begin
  Result := [AScope];
  // Auf Datei-Ebene stehen die Marken in den Abschnitten.
  if AScope.Kind = TSyntaxKind.RoutineDecl then
  begin
    Exit;
  end;
  for mIndex := 0 to AScope.ChildCount - 1 do
  begin
    if AScope[mIndex].Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection] then
    begin
      Result := Result + [AScope[mIndex]];
    end;
  end;
end;

procedure TTreeChecker.AddSectionLabels(ASection: TSyntaxNode; var AResult: TArray<string>);
var
  mTokenIndex: Integer;
begin
  mTokenIndex := IndexAt(ASection.StartOffset);
  if mTokenIndex < 0 then
  begin
    Exit;
  end;
  mTokenIndex := NextCode(mTokenIndex);
  while (mTokenIndex >= 0) and (FTokens[mTokenIndex].Offset < ASection.EndOffset) do
  begin
    if FTokens[mTokenIndex].Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Number] then
    begin
      AResult := AResult + [LabelKey(FTokens[mTokenIndex].Text)];
    end;
    mTokenIndex := NextCode(mTokenIndex);
  end;
end;

function TTreeChecker.LabelsOf(AScope: TSyntaxNode): TArray<string>;
var
  mInner: Integer;
  mContainer: TSyntaxNode;
begin
  Result := nil;
  for mContainer in LabelContainers(AScope) do
  begin
    for mInner := 0 to mContainer.ChildCount - 1 do
    begin
      if mContainer[mInner].Kind = TSyntaxKind.LabelSection then
      begin
        AddSectionLabels(mContainer[mInner], Result);
      end;
    end;
  end;
end;

function TTreeChecker.GotoScope(AGoto: TSyntaxNode): TSyntaxNode;
begin
  Result := AGoto.Parent;
  while (Result <> nil) and (Result.Parent <> nil) and (Result.Kind <> TSyntaxKind.RoutineDecl) do
  begin
    // Marken anonymer Methoden kennt der Baum nicht sicher genug.
    if Result.Kind = TSyntaxKind.AnonymousMethod then
    begin
      Exit(nil);
    end;
    Result := Result.Parent;
  end;
end;

function TTreeChecker.LabelVisible(AScope: TSyntaxNode; const AKey: string): Boolean;
var
  mOuter: TSyntaxNode;
begin
  Result := IndexStr(AKey, LabelsOf(AScope)) >= 0;
  // In einer umgebenden Routine deklariert: das meldet label-misuse genauer (E2093, #995).
  mOuter := AScope.Parent;
  while not Result and (mOuter <> nil) do
  begin
    Result := (mOuter.Kind = TSyntaxKind.RoutineDecl) and (IndexStr(AKey, LabelsOf(mOuter)) >= 0);
    mOuter := mOuter.Parent;
  end;
end;

procedure TTreeChecker.CheckGoto(AGoto: TSyntaxNode);
var
  mScope: TSyntaxNode;
  mNameIndex: Integer;
begin
  if AGoto.Name = '' then
  begin
    Exit;
  end;
  mScope := GotoScope(AGoto);
  if (mScope = nil) or LabelVisible(mScope, LabelKey(AGoto.Name)) then
  begin
    Exit;
  end;
  mNameIndex := IndexAt(AGoto.StartOffset);
  if mNameIndex >= 0 then
  begin
    mNameIndex := NextCode(mNameIndex);
  end;
  if mNameIndex < 0 then
  begin
    Exit;
  end;
  Add('E2031', cTexts[TSyntaxChecksText.LabelExpectedIsNotDeclared].Fmt([AGoto.Name]),
    FTokens[mNameIndex].StartPos, FTokens[mNameIndex].EndPos);
end;

function TTreeChecker.Run(ARoot: TSyntaxNode): TArray<TSyntaxDiagnostic>;
begin
  CollectDeclared(ARoot);
  ARoot.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := True;
      case ANode.Kind of
        TSyntaxKind.RoutineHeader:
          if (ANode.Parent <> nil) and ((ANode.Parent.Kind = TSyntaxKind.RoutineDecl) or
            (ANode.Parent.Kind in cTypeKinds)) then
          begin
            CheckHeader(ANode);
            CheckClassOperator(ANode);
          end;
        TSyntaxKind.Parameter:
          CheckParameter(ANode);
        TSyntaxKind.VarDecl:
          CheckVarDecl(ANode);
        TSyntaxKind.Field:
          CheckFieldType(ANode);
        TSyntaxKind.TypeDecl:
          CheckTypeDecl(ANode);
        TSyntaxKind.LabelSection:
          if (ANode.Parent <> nil) and (ANode.Parent.Kind = TSyntaxKind.InterfaceSection) then
          begin
            Add('E2049', cTexts[TSyntaxChecksText.LabelDeclarationsAreNotAllowed].Text, ANode.StartPos, ANode.EndPos);
          end;
        TSyntaxKind.GotoStatement:
          CheckGoto(ANode);
      else
        // Übrige Werte bewusst ohne Wirkung.
      end;
    end);
  Result := FResult.ToArray;
end;

{ TSyntaxChecks }

class function TSyntaxChecks.Check(ARoot: TSyntaxNode; const ATokens: TArray<TPascalToken>):
  TArray<TSyntaxDiagnostic>;
var
  mChecker: TTreeChecker;
begin
  if ARoot = nil then
  begin
    Exit(nil);
  end;
  mChecker := TTreeChecker.Create(ATokens);
  try
    Result := mChecker.Run(ARoot);
  finally
    mChecker.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Pascal.SyntaxChecks', cTexts);

end.
