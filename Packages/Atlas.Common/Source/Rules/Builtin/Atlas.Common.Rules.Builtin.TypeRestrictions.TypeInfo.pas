unit Atlas.Common.Rules.Builtin.TypeRestrictions.TypeInfo;

// Regel aus TypeRestrictions, registriert mit RegisterTypeRestrictionRules:
//   typeinfo-invalid              TypeInfo bzw. Default mit einer Variablen
//                                 statt eines Typs (#1084, E2133, E2537;
//                                 Parameter, lokale, Inline- und Unit-
//                                 Variablen, Felder, Properties, Result;
//                                 Korrektur: Typ der Variablen einsetzen),
//                                 TypeInfo eines Typs ohne RTTI (Aufzählung
//                                 mit festen Werten, Dateityp, Text; E2134)
//                                 und Default eines Dateityps (E2538). Namen
//                                 werden von innen nach außen aufgelöst; in
//                                 with, in Helfern, in Methoden fremder Typen
//                                 und bei eigenen Routinen TypeInfo bzw.
//                                 Default bleibt die Regel still.

interface

uses
  Atlas.Common.Rules.Contract;

const
  cTypeInfoInvalidRuleId = 'typeinfo-invalid';

type
  TTypeInfoInvalidRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Pascal.ConditionalBranches,
  Atlas.Common.Rules.Builtin.Inheritance,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Rules.Builtin.TypeRestrictions.Heads,
  Atlas.Common.Rules.Builtin.TypeRestrictions.Symbols,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TTypeRestrictionsTypeInfoText = (Title, VariableMeant, InsertCall, Variable, FileRtti, DefaultFileAssign,
    DefaultFile, EnumRtti);

const
  cTexts: array[TTypeRestrictionsTypeInfoText] of TAtlasText = (
    (De: 'TypeInfo oder Default mit unzulässigem Argument'; En: 'TypeInfo or Default with invalid argument'),
    (De: '%s erwartet einen Typ, %s ist eine Variable; gemeint ist %s(%s) (wie %s).';
     En: '%s expects a type, %s is a variable; %s(%s) is meant (like %s).'),
    (De: '%s(%s) einsetzen'; En: 'Insert %s(%s)'),
    (De: '%s erwartet einen Typ, %s ist eine Variable (wie %s).'; En: '%s expects a type, %s is a variable (like %s).'),
    (De: '%s hat keine Typinformation: Dateitypen erzeugen keine RTTI (wie E2134).';
     En: '%s has no type information: file types produce no RTTI (like E2134).'),
    (De: 'Default ist für den Dateityp %s nicht erlaubt, und Dateivariablen lassen sich nicht zuweisen (wie E2538 ' +
      'und E2015).';
     En: 'Default is not allowed for the file type %s, and file variables cannot be assigned (like E2538 and E2015).'),
    (De: 'Default ist für den Dateityp %s nicht erlaubt (wie E2538).';
     En: 'Default is not allowed for the file type %s (like E2538).'),
    (De: '%s hat keine Typinformation: Aufzählungen mit festen Werten erzeugen keine RTTI (wie E2134).';
     En: '%s has no type information: enumerations with fixed values produce no RTTI (like E2134).'));

{$SCOPEDENUMS OFF}

{ TTypeInfoInvalidRule }

type
  /// <summary>Was ein Name an einer Stelle sicher ist: nichts in der Datei gefunden, Variable (auch Parameter,
  /// Feld, Property, Result), Typ, etwas anderes oder unsicher (with, Helfer, fremde Klasse, bedingte
  /// Zweige).</summary>
  TNameMeaning = (NotFound, Variable, TypeName, Other, Uncertain);

  /// <summary>Ergebnis der Auflösung: Bedeutung, Deklaration und – bei Variablen – der Typknoten oder nil.</summary>
  TNameResolution = record
    Meaning: TNameMeaning;
    Decl: TSyntaxNode;
    TypeNode: TSyntaxNode;
    class function Create(AMeaning: TNameMeaning; ADecl, ATypeNode: TSyntaxNode): TNameResolution; static;
  end;

class function TNameResolution.Create(AMeaning: TNameMeaning; ADecl, ATypeNode: TSyntaxNode): TNameResolution;
begin
  Result.Meaning := AMeaning;
  Result.Decl := ADecl;
  Result.TypeNode := ATypeNode;
end;

/// <summary>Kommt AName in der Namensliste ANames ("A,B") vor?</summary>
function InNameList(const ANames, AName: string): Boolean;
var
  mName: string;
begin
  for mName in SplitString(ANames, ',') do
  begin
    if SameText(Trim(mName), AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Erster Kindknoten, der einen Typ beschreibt (TypeReference, ArrayType …), nil ohne.</summary>
function TypeChild(ANode: TSyntaxNode): TSyntaxNode;
var
  mIndex: Integer;
begin
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    if ANode[mIndex].Kind in [TSyntaxKind.TypeReference, TSyntaxKind.ArrayType, TSyntaxKind.RecordType,
      TSyntaxKind.SetType, TSyntaxKind.EnumType, TSyntaxKind.PointerType, TSyntaxKind.FileType,
      TSyntaxKind.ProcedureType, TSyntaxKind.SubrangeType, TSyntaxKind.ClassOfType] then
    begin
      Exit(ANode[mIndex]);
    end;
  end;
  Result := nil;
end;

function Unresolved: TNameResolution;
begin
  Result := TNameResolution.Create(TNameMeaning.NotFound, nil, nil);
end;

/// <summary>Bedeutung der Deklaration ADecl aus einem var-, const- oder type-Abschnitt.</summary>
function DeclResolution(ADecl: TSyntaxNode): TNameResolution;
begin
  case ADecl.Kind of
    TSyntaxKind.VarDecl:
      Result := TNameResolution.Create(TNameMeaning.Variable, ADecl, TypeChild(ADecl));
    TSyntaxKind.TypeDecl:
      Result := TNameResolution.Create(TNameMeaning.TypeName, ADecl, nil);
  else
    Result := TNameResolution.Create(TNameMeaning.Other, ADecl, nil);
  end;
end;

/// <summary>Letzte Deklaration AName in einem var-, const- oder type-Abschnitt; AResolution bleibt sonst.</summary>
procedure MatchDeclSection(ASection: TSyntaxNode; const AName: string; var AResolution: TNameResolution);
var
  mIndex: Integer;
  mDecl: TSyntaxNode;
begin
  for mIndex := 0 to ASection.ChildCount - 1 do
  begin
    mDecl := ASection[mIndex];
    if (mDecl.Kind in [TSyntaxKind.VarDecl, TSyntaxKind.ConstDecl, TSyntaxKind.TypeDecl]) and
      InNameList(mDecl.Name, AName) then
    begin
      AResolution := DeclResolution(mDecl);
    end;
  end;
end;

/// <summary>Letzte Unit AName einer uses-Klausel; AResolution bleibt sonst.</summary>
procedure MatchUses(AUses: TSyntaxNode; const AName: string; var AResolution: TNameResolution);
var
  mIndex: Integer;
begin
  for mIndex := 0 to AUses.ChildCount - 1 do
  begin
    if SameText(LastPart(AUses[mIndex].Name), AName) then
    begin
      AResolution := TNameResolution.Create(TNameMeaning.Other, AUses[mIndex], nil);
    end;
  end;
end;

/// <summary>Deklariert der Abschnitt ASection (Kind eines Halters) den Namen AName? AResolution bleibt sonst.
/// </summary>
procedure MatchSection(ASection: TSyntaxNode; const AName: string; var AResolution: TNameResolution);
begin
  case ASection.Kind of
    TSyntaxKind.VarSection, TSyntaxKind.ConstSection, TSyntaxKind.TypeSection:
      MatchDeclSection(ASection, AName, AResolution);
    TSyntaxKind.Field:
      if InNameList(ASection.Name, AName) then
      begin
        AResolution := TNameResolution.Create(TNameMeaning.Variable, ASection, TypeChild(ASection));
      end;
    TSyntaxKind.PropertyDecl:
      if SameText(ASection.Name, AName) then
      begin
        AResolution := TNameResolution.Create(TNameMeaning.Variable, ASection, TypeChild(ASection));
      end;
    TSyntaxKind.RoutineDecl, TSyntaxKind.RoutineHeader:
      if SameText(LastPart(ASection.Name), AName) and (Pos('.', ASection.Name) = 0) then
      begin
        AResolution := TNameResolution.Create(TNameMeaning.Other, ASection, nil);
      end;
    TSyntaxKind.UsesClause:
      MatchUses(ASection, AName, AResolution);
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

/// <summary>Sucht AName in den Deklarationsabschnitten unter AHolder (Routine, anonyme Methode, Klasse, Unit-
/// Abschnitt), nur vor ABefore (-1: alle). Variablen und Felder: Variable, Typen: TypeName, sonst Other.</summary>
function FindInSections(AHolder: TSyntaxNode; const AName: string; ABefore: Integer;
  out AResolution: TNameResolution): Boolean;
var
  mIndex: Integer;
begin
  AResolution := Unresolved;
  for mIndex := 0 to AHolder.ChildCount - 1 do
  begin
    if (ABefore >= 0) and (AHolder[mIndex].StartOffset >= ABefore) then
    begin
      Break;
    end;
    MatchSection(AHolder[mIndex], AName, AResolution);
  end;
  Result := AResolution.Meaning <> TNameMeaning.NotFound;
end;

/// <summary>Letzter Parameter AName unter AParameters; AResolution bleibt sonst.</summary>
procedure MatchParameters(AParameters: TSyntaxNode; const AName: string; var AResolution: TNameResolution);
var
  mIndex: Integer;
  mParam: TSyntaxNode;
begin
  for mIndex := 0 to AParameters.ChildCount - 1 do
  begin
    mParam := AParameters[mIndex];
    if (mParam.Kind = TSyntaxKind.Parameter) and InNameList(mParam.Name, AName) then
    begin
      AResolution := TNameResolution.Create(TNameMeaning.Variable, mParam, TypeChild(mParam));
    end;
  end;
end;

/// <summary>Letzter Typparameter AName unter AParams; AResolution bleibt sonst.</summary>
procedure MatchGenericParams(AParams: TSyntaxNode; const AName: string; var AResolution: TNameResolution);
var
  mIndex: Integer;
begin
  for mIndex := 0 to AParams.ChildCount - 1 do
  begin
    if SameText(AParams[mIndex].Name, AName) then
    begin
      AResolution := TNameResolution.Create(TNameMeaning.TypeName, AParams[mIndex], nil);
    end;
  end;
end;

/// <summary>Parameter, Typparameter und Result eines Routinenkopfs.</summary>
function FindInHeader(AHeader: TSyntaxNode; const AName: string; out AResolution: TNameResolution): Boolean;
var
  mIndex: Integer;
  mResultType: TSyntaxNode;
begin
  AResolution := Unresolved;
  for mIndex := 0 to AHeader.ChildCount - 1 do
  begin
    case AHeader[mIndex].Kind of
      TSyntaxKind.Parameters:
        MatchParameters(AHeader[mIndex], AName, AResolution);
      TSyntaxKind.GenericParams:
        MatchGenericParams(AHeader[mIndex], AName, AResolution);
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
  end;
  mResultType := AHeader.FindChild(TSyntaxKind.TypeReference);
  if (AResolution.Meaning = TNameMeaning.NotFound) and SameText(AName, 'Result') and (mResultType <> nil) then
  begin
    AResolution := TNameResolution.Create(TNameMeaning.Variable, AHeader, mResultType);
  end;
  Result := AResolution.Meaning <> TNameMeaning.NotFound;
end;

/// <summary>Inline-Variable oder -Konstante AName im Block ABlock vor dessen Kind AChild.</summary>
function FindInlineBefore(ABlock, AChild: TSyntaxNode; const AName: string; out AResolution: TNameResolution):
  Boolean;
var
  mPosition, mIndex: Integer;
  mDecl: TSyntaxNode;
begin
  AResolution := Unresolved;
  mPosition := ABlock.ChildCount - 1;
  while (mPosition >= 0) and (ABlock[mPosition] <> AChild) do
  begin
    Dec(mPosition);
  end;
  for mIndex := mPosition - 1 downto 0 do
  begin
    mDecl := ABlock[mIndex];
    if not (mDecl.Kind in [TSyntaxKind.InlineVar, TSyntaxKind.InlineConst]) or not InNameList(mDecl.Name, AName) then
    begin
      Continue;
    end;
    if mDecl.Kind = TSyntaxKind.InlineVar then
    begin
      AResolution := TNameResolution.Create(TNameMeaning.Variable, mDecl, TypeChild(mDecl));
    end
    else
    begin
      AResolution := TNameResolution.Create(TNameMeaning.Other, mDecl, nil);
    end;
    Exit(True);
  end;
  Result := False;
end;

/// <summary>Unit-Ebene: im implementation-Teil zuerst die eigenen Deklarationen vor ABefore, dann der
/// interface-Teil; NotFound ohne Treffer.</summary>
procedure ResolveInUnitSection(ASection: TSyntaxNode; const AName: string; ABefore: Integer;
  out AResolution: TNameResolution);
var
  mInterface: TSyntaxNode;
begin
  if FindInSections(ASection, AName, ABefore, AResolution) then
  begin
    Exit;
  end;
  if (ASection.Kind = TSyntaxKind.ImplementationSection) and (ASection.Parent <> nil) then
  begin
    mInterface := ASection.Parent.FindChild(TSyntaxKind.InterfaceSection);
    if mInterface <> nil then
    begin
      FindInSections(mInterface, AName, -1, AResolution);
    end;
  end;
end;

type
  /// <summary>Aufruf TypeInfo(X) bzw. Default(X): Knoten, Argument und Name.</summary>
  TIntrinsicCall = record
    Call: TSyntaxNode;
    Argument: TSyntaxNode;
    /// <summary>TypeInfo oder Default, wie geschrieben.</summary>
    Intrinsic: string;
    /// <summary>Name im Argument.</summary>
    Name: string;
    IsTypeInfo: Boolean;
  end;

/// <summary>Steht der Aufruf rechts in einer Zuweisung?</summary>
function AssignedFrom(ACall: TSyntaxNode): Boolean;
begin
  Result := (ACall.Parent <> nil) and (ACall.Parent.Kind = TSyntaxKind.AssignStatement);
  Result := Result and (ACall.Parent.ChildCount > 1) and (ACall.Parent[1] = ACall);
end;

function HasExplicitValues(AEnum: TSyntaxNode): Boolean;
var
  mIndex: Integer;
begin
  for mIndex := 0 to AEnum.ChildCount - 1 do
  begin
    if AEnum[mIndex].Kind <> TSyntaxKind.Identifier then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TTypeInfoInvalidRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cTypeInfoInvalidRuleId, TRuleSeverity.Error,
    cTexts[TTypeRestrictionsTypeInfoText.Title].Text);
end;

procedure TTypeInfoInvalidRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TArray<TPascalToken>;
  mTypes: TFileTypes;
  mPaths: TArray<string>;
  mCalls: TList<TSyntaxNode>;
  mNames: TDeclarationNames;
  mCallNode: TSyntaxNode;

  function PathOf(ANode: TSyntaxNode): string;
  begin
    Result := TConditionalBranches.PathAt(mPaths, TRoutineBody.TokenAt(mTokens, ANode.StartOffset));
  end;

  /// <summary>Mitglieder des Typs, zu dem die Methode ARoutine gehört; Uncertain, wenn der Typ nicht in der Datei
  /// steht oder ein Helfer ist. Vorfahren außerhalb der Datei bleiben unbeachtet.</summary>
  function FindInOwner(ARoutine: TSyntaxNode; const AName: string; out AResolution: TNameResolution): Boolean;
  var
    mQualifier: string;
    mIndex: Integer;
    mDecl, mStruct: TSyntaxNode;
  begin
    AResolution := TNameResolution.Create(TNameMeaning.Uncertain, nil, nil);
    mQualifier := Copy(ARoutine.Name, 1, LastDelimiter('.', ARoutine.Name) - 1);
    mIndex := mTypes.IndexOf(BareTypeName(mQualifier));
    if mIndex < 0 then
    begin
      Exit(True);
    end;
    mStruct := mTypes.Types[mIndex];
    if not (mStruct.Kind in [TSyntaxKind.ClassType, TSyntaxKind.RecordType, TSyntaxKind.ObjectType]) then
    begin
      Exit(True);
    end;
    if FindInSections(mStruct, AName, -1, AResolution) then
    begin
      Exit(True);
    end;
    mDecl := mStruct.Parent;
    Result := (mDecl <> nil) and FindInHeader(mDecl, AName, AResolution);
  end;

  /// <summary>Namen in der Routine ARoutine: Kopf, Abschnitte, ihr eigener Name, Mitglieder des eigenen Typs.
  /// </summary>
  function ResolveInRoutine(ARoutine: TSyntaxNode; const AName: string; out AResolution: TNameResolution): Boolean;
  var
    mHeader: TSyntaxNode;
  begin
    mHeader := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
    Result := (mHeader <> nil) and FindInHeader(mHeader, AName, AResolution);
    Result := Result or FindInSections(ARoutine, AName, -1, AResolution);
    if not Result and SameText(LastPart(ARoutine.Name), AName) then
    begin
      AResolution := TNameResolution.Create(TNameMeaning.Other, ARoutine, nil);
      Result := True;
    end;
    if not Result and (Pos('.', ARoutine.Name) > 0) then
    begin
      Result := FindInOwner(ARoutine, AName, AResolution);
    end;
  end;

  /// <summary>Bedeutung von AName (gesucht an AStart) auf der Ebene über ANode; False, wenn weiter außen gesucht
  /// werden muss.</summary>
  function ResolveAt(AStart, ANode: TSyntaxNode; const AName: string; out AResolution: TNameResolution): Boolean;
  var
    mParent: TSyntaxNode;
  begin
    mParent := ANode.Parent;
    AResolution := Unresolved;
    Result := False;
    case mParent.Kind of
      TSyntaxKind.WithStatement:
        if ANode = mParent[mParent.ChildCount - 1] then
        begin
          AResolution := TNameResolution.Create(TNameMeaning.Uncertain, nil, nil);
          Result := True;
        end;
      TSyntaxKind.Block:
        Result := FindInlineBefore(mParent, ANode, AName, AResolution);
      TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.ExceptionHandler:
        if SameText(mParent.Name, AName) then
        begin
          AResolution := TNameResolution.Create(TNameMeaning.Variable, mParent, TypeChild(mParent));
          Result := True;
        end;
      TSyntaxKind.AnonymousMethod:
        Result := FindInHeader(mParent, AName, AResolution) or FindInSections(mParent, AName, -1, AResolution);
      TSyntaxKind.RoutineDecl:
        Result := ResolveInRoutine(mParent, AName, AResolution);
      TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection:
        begin
          ResolveInUnitSection(mParent, AName, AStart.StartOffset, AResolution);
          Result := True;
        end;
      TSyntaxKind.ProgramFile, TSyntaxKind.LibraryFile:
        begin
          FindInSections(mParent, AName, AStart.StartOffset, AResolution);
          Result := True;
        end;
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
  end;

  /// <summary>Bedeutung von AName an der Stelle ANode, von innen nach außen.</summary>
  function Resolve(ANode: TSyntaxNode; const AName: string): TNameResolution;
  var
    mNode: TSyntaxNode;
  begin
    mNode := ANode;
    while mNode.Parent <> nil do
    begin
      if ResolveAt(ANode, mNode, AName, Result) then
      begin
        Exit;
      end;
      mNode := mNode.Parent;
    end;
    Result := Unresolved;
  end;

  /// <summary>Typknoten hinter dem Typnamen ADecl (TypeDecl), Aliase in der Datei verfolgt; nil bei unsicheren.
  /// </summary>
  function TypeBehind(ADecl: TSyntaxNode): TSyntaxNode;
  var
    mDepth, mIndex: Integer;
  begin
    Result := TypeChild(ADecl);
    for mDepth := 1 to 16 do
    begin
      if (Result = nil) or (Result.Kind <> TSyntaxKind.TypeReference) then
      begin
        Exit;
      end;
      if (Pos('.', Result.Name) > 0) or (Result.FindChild(TSyntaxKind.GenericArgs) <> nil) then
      begin
        Exit(nil);
      end;
      mIndex := mTypes.IndexOf(Result.Name);
      if mIndex < 0 then
      begin
        Exit;
      end;
      Result := mTypes.Types[mIndex];
    end;
    Result := nil;
  end;

  /// <summary>Deklariert eine Unit im Index AName auf oberster Ebene (eigene Routine Default o. ä.)?</summary>
  function DeclaredInIndex(const AName: string): Boolean;
  var
    mLocation: TSymbolLocation;
  begin
    if AContext.Index = nil then
    begin
      Exit(False);
    end;
    for mLocation in AContext.Index.FindSymbols(AName) do
    begin
      if mLocation.Symbol.Container = '' then
      begin
        Exit(True);
      end;
    end;
    Result := False;
  end;

  procedure ReportVariable(const ACall: TIntrinsicCall; const AResolution: TNameResolution);
  var
    mTypeText, mCode: string;
  begin
    mCode := 'E2537';
    if ACall.IsTypeInfo then
    begin
      mCode := 'E2133';
    end;
    mTypeText := '';
    if (AResolution.TypeNode <> nil) and (AResolution.TypeNode.Kind = TSyntaxKind.TypeReference) then
    begin
      mTypeText := OneLine(AContext.Text, AResolution.TypeNode);
    end;
    if mTypeText <> '' then
    begin
      AReport.Add(NodeRange(ACall.Argument), cTexts[TTypeRestrictionsTypeInfoText.VariableMeant].Fmt([ACall.Intrinsic,
        ACall.Name, ACall.Intrinsic, mTypeText, mCode]), TRuleConfidence.High,
        [TRuleFix.Create(cTexts[TTypeRestrictionsTypeInfoText.InsertCall].Fmt([ACall.Intrinsic, mTypeText]),
        [TRuleEdit.Create(NodeRange(ACall.Argument), mTypeText)])]);
    end
    else
    begin
      AReport.Add(NodeRange(ACall.Argument), cTexts[TTypeRestrictionsTypeInfoText.Variable].Fmt(
        [ACall.Intrinsic, ACall.Name, mCode]), TRuleConfidence.High, nil);
    end;
  end;

  procedure ReportFileType(const ACall: TIntrinsicCall);
  begin
    if ACall.IsTypeInfo then
    begin
      AReport.Add(NodeRange(ACall.Argument), cTexts[TTypeRestrictionsTypeInfoText.FileRtti].Fmt([ACall.Name]),
        TRuleConfidence.High, nil);
    end
    else if AssignedFrom(ACall.Call) then
    begin
      // Die Zuweisung an eine Dateivariable meldet dcc zusätzlich als E2015.
      AReport.Add(NodeRange(ACall.Argument), cTexts[TTypeRestrictionsTypeInfoText.DefaultFileAssign].Fmt([ACall.Name]),
        TRuleConfidence.High,
        nil);
    end
    else
    begin
      AReport.Add(NodeRange(ACall.Argument), cTexts[TTypeRestrictionsTypeInfoText.DefaultFile].Fmt(
        [ACall.Name]), TRuleConfidence.High, nil);
    end;
  end;

  /// <summary>Ist der nicht gefundene Name Text, TextFile oder file aus System? Eine gleichnamige Deklaration der
  /// Datei macht still.</summary>
  function IsBuiltinFile(const ACall: TIntrinsicCall): Boolean;
  begin
    Result := not mNames.Declared(ACall.Name) and (mTypes.IndexOf(ACall.Name) < 0);
    Result := Result and (MatchText(ACall.Name, ['Text', 'TextFile']) or
      (not ACall.IsTypeInfo and SameText(ACall.Name, 'File')));
  end;

  /// <summary>Typknoten hinter dem gefundenen Typnamen, nil bei unsicheren.</summary>
  function DeclaredTypeBehind(const AResolution: TNameResolution): TSyntaxNode;
  begin
    Result := nil;
    if AResolution.Decl.Kind = TSyntaxKind.TypeDecl then
    begin
      Result := TypeBehind(AResolution.Decl);
    end;
  end;

  procedure CheckTypeArgument(const ACall: TIntrinsicCall; const AResolution: TNameResolution);
  var
    mBehind: TSyntaxNode;
  begin
    if AResolution.Meaning = TNameMeaning.NotFound then
    begin
      if IsBuiltinFile(ACall) then
      begin
        ReportFileType(ACall);
      end;
      Exit;
    end;
    mBehind := DeclaredTypeBehind(AResolution);
    if mBehind = nil then
    begin
      Exit;
    end;
    if mBehind.Kind = TSyntaxKind.FileType then
    begin
      ReportFileType(ACall);
    end
    else if ACall.IsTypeInfo and (mBehind.Kind = TSyntaxKind.EnumType) and HasExplicitValues(mBehind) then
    begin
      AReport.Add(NodeRange(ACall.Argument), cTexts[TTypeRestrictionsTypeInfoText.EnumRtti].Fmt([ACall.Name]),
        TRuleConfidence.High, nil);
    end;
  end;

  procedure CheckCall(ACallNode: TSyntaxNode);
  var
    mCall: TIntrinsicCall;
    mResolution: TNameResolution;
  begin
    mCall := Default(TIntrinsicCall);
    mCall.Call := ACallNode;
    mCall.Argument := ACallNode[1];
    if mCall.Argument.Kind <> TSyntaxKind.Identifier then
    begin
      Exit;
    end;
    mCall.Intrinsic := ACallNode[0].Name;
    mCall.IsTypeInfo := SameText(mCall.Intrinsic, 'TypeInfo');
    mCall.Name := mCall.Argument.Name;
    mResolution := Resolve(ACallNode, mCall.Name);
    if (mResolution.Decl <> nil) and (mResolution.Meaning in [TNameMeaning.Variable, TNameMeaning.TypeName]) and
      not TConditionalBranches.Implies(PathOf(ACallNode), PathOf(mResolution.Decl)) then
    begin
      Exit;
    end;
    case mResolution.Meaning of
      TNameMeaning.Variable:
        ReportVariable(mCall, mResolution);
      TNameMeaning.NotFound, TNameMeaning.TypeName:
        CheckTypeArgument(mCall, mResolution);
    else
      // Other und Uncertain: still.
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or
    not (ContainsText(AContext.Text, 'TypeInfo') or ContainsText(AContext.Text, 'Default')) then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  mTypes := TFileTypes.Collect(AContext.Tree.Root);
  mPaths := TConditionalBranches.Paths(mTokens);
  mNames := nil;
  mCalls := TList<TSyntaxNode>.Create;
  try
    AContext.Tree.Root.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        Result := True;
        if (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount = 2) and
          (ANode[0].Kind = TSyntaxKind.Identifier) and MatchText(ANode[0].Name, ['TypeInfo', 'Default']) then
        begin
          mCalls.Add(ANode);
        end;
      end);
    if mCalls.Count = 0 then
    begin
      Exit;
    end;
    mNames := TDeclarationNames.Create(AContext.Tree.Root);
    for mCallNode in mCalls do
    begin
      // Eine eigene Routine TypeInfo bzw. Default (Datei oder Index) verdeckt die des Compilers.
      if not mNames.Declared(mCallNode[0].Name) and not DeclaredInIndex(mCallNode[0].Name) then
      begin
        CheckCall(mCallNode);
      end;
    end;
  finally
    mNames.Free;
    mCalls.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.TypeRestrictions.TypeInfo', cTexts);

end.
