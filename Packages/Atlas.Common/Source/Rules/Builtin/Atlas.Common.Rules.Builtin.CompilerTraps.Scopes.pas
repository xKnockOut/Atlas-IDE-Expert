unit Atlas.Common.Rules.Builtin.CompilerTraps.Scopes;

// Namen, die Free Pascal findet, Delphi aber nicht oder anders (#2095, Gruppe Compiler vorab):
//   class-constant-unqualified  Ein Bezeichner ohne Klassennamen ist eine Konstante einer anderen Klasse bzw. eines
//                               anderen Records derselben Unit (cHeadCacheMs aus TWorkingCopies in einer Methode von
//                               TWorkingHeads), oder in der Deklaration einer Klasse eine Konstante eines Vorfahren
//                               (cRows = 2 * cGap): Delphi sieht beide dort nicht (wie E2003). Still, wenn ein
//                               lokaler Name, ein Mitglied der eigenen Klasse samt Vorfahren und umgebenden Klassen
//                               oder ein Name der Unit-Ebene so heißt, und in Routinen mit with. Korrektur (sicher):
//                               Klassennamen davor setzen.
//   enum-hides-keyword          Aufzählung ohne {$SCOPEDENUMS ON} mit einem Wert Continue, Break, Exit oder Halt: Der
//                               Wert verdeckt die Standardprozedur in jeder Unit, die den Typ sieht; Continue; wird
//                               dort zum Ausdruck (wie E2014).
//   inline-reference-type       reference to direkt als Typ eines Felds oder einer Variablen: Delphi kennt
//                               Methodenreferenztypen nur als benannten Typ (wie E2003 'reference'); FPC nimmt die
//                               Schreibweise an.
//   member-hides-unit-symbol    In einer Methode steht ohne Unit-Namen ein Name, den die Unit als Routine, Konstante
//                               oder Variable deklariert und den die Klasse von einem Vorfahren erbt (Scaled
//                               aus TCustomForm, AddLabel eines Vorfahren, Padding aus TControl). Delphi nimmt das
//                               Mitglied (je nach Gebrauch E2066, E2010, E2015 oder E2034). Vorfahren außerhalb der
//                               Datei kommen aus dem Symbolindex. Korrektur: Unit-Namen davor setzen.

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  cClassConstantUnqualifiedRuleId = 'class-constant-unqualified';
  cEnumHidesKeywordRuleId = 'enum-hides-keyword';
  cInlineReferenceTypeRuleId = 'inline-reference-type';
  cMemberHidesUnitSymbolRuleId = 'member-hides-unit-symbol';

type
  TClassConstantUnqualifiedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TEnumHidesKeywordRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TInlineReferenceTypeRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TMemberHidesUnitSymbolRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

/// <summary>Meldet die vier Regeln in ARegistry an.</summary>
procedure RegisterCompilerTrapScopeRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.RoutineSignatures,
  Atlas.Common.Index.Contract,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TScopeTrapText = (ConstTitle, ConstForeign, ConstInherited, ConstFix, EnumTitle, EnumMessage, ReferenceTitle,
    ReferenceMessage, HiddenTitle, HiddenMessage, HiddenFix);

const
  cTexts: array[TScopeTrapText] of TAtlasText = (
    (De: 'Konstante einer anderen Klasse ohne Klassennamen'; En: 'Constant of another class without class name'),
    (De: '%s ist eine Konstante von %s; in %s sieht Delphi sie ohne Klassennamen nicht (wie E2003). %1:s.%0:s ' +
      'schreiben.';
     En: '%s is a constant of %s; in %s Delphi does not see it without the class name (like E2003). Write ' +
      '%1:s.%0:s.'),
    (De: '%s ist eine Konstante des Vorfahren %s; in der Deklaration von %s sieht Delphi geerbte Konstanten noch ' +
      'nicht (wie E2003). %1:s.%0:s schreiben.';
     En: '%s is a constant of the ancestor %s; in the declaration of %s Delphi does not see inherited constants yet ' +
      '(like E2003). Write %1:s.%0:s.'),
    (De: '%s.%s schreiben'; En: 'Write %s.%s'),
    (De: 'Aufzählungswert verdeckt eine Standardprozedur'; En: 'Enumeration value hides a standard procedure'),
    (De: 'Der Wert %s von %s verdeckt ohne {$SCOPEDENUMS ON} die Standardprozedur %0:s in jeder Unit, die den Typ ' +
      'sieht; %0:s; wird dort zum Ausdruck (wie E2014). {$SCOPEDENUMS ON} vor den Typ setzen oder den Wert ' +
      'umbenennen.';
     En: 'Without {$SCOPEDENUMS ON} the value %s of %s hides the standard procedure %0:s in every unit that sees ' +
      'the type; %0:s; becomes an expression there (like E2014). Put {$SCOPEDENUMS ON} before the type or rename ' +
      'the value.'),
    (De: 'reference to ohne benannten Typ'; En: 'reference to without a named type'),
    (De: '%s hat den Typ reference to … direkt; Delphi kennt Methodenreferenzen nur als benannten Typ (wie E2003 ' +
      '''reference''). Typ im type-Abschnitt deklarieren und hier verwenden.';
     En: '%s has the type reference to … directly; Delphi only knows method references as a named type (like E2003 ' +
      '''reference''). Declare the type in a type section and use it here.'),
    (De: 'Mitglied verdeckt einen Namen der Unit'; En: 'Member hides a name of the unit'),
    (De: '%0:s meint in Methoden von %1:s das Mitglied %2:s.%0:s, nicht %0:s der Unit (Zeile %3:d); Delphi nimmt ' +
      'das Mitglied (wie E2066, E2010, E2015 bzw. E2034). %4:s.%0:s schreiben oder umbenennen.';
     En: 'In methods of %1:s, %0:s means the member %2:s.%0:s, not %0:s of the unit (line %3:d); Delphi takes the ' +
      'member (like E2066, E2010, E2015 or E2034). Write %4:s.%0:s or rename it.'),
    (De: '%s.%s schreiben'; En: 'Write %s.%s'));

{$SCOPEDENUMS OFF}

const
  /// <summary>Standardprozeduren, die ein gleichnamiger Aufzählungswert verdeckt.</summary>
  cHiddenKeywords: array[0..3] of string = ('Continue', 'Break', 'Exit', 'Halt');
  cScopedEnumsDirective = 'SCOPEDENUMS';

type
  TNameSet = TDictionary<string, Boolean>;

  /// <summary>Eine Klasse bzw. ein Record der Datei.</summary>
  TScopeClass = class
  public
    /// <summary>Name wie in der Implementierung der Methoden: "TAussen.TInnen", ohne Typparameter.</summary>
    Name: string;
    /// <summary>Name ohne umgebende Typen: "TInnen".</summary>
    ShortName: string;
    /// <summary>Vollständiger Name des umgebenden Typs; '' auf Unit-Ebene.</summary>
    Outer: string;
    /// <summary>Name des Vorfahren wie im Quelltext, ohne Unit und Typargumente; '' ohne.</summary>
    Ancestor: string;
    Node: TSyntaxNode;
    Members: TNameSet;
    Constants: TNameSet;
    constructor Create;
    destructor Destroy; override;
  end;

  /// <summary>Klassen, Konstanten und Namen der Unit-Ebene einer Datei für class-constant-unqualified.</summary>
  TScopeModel = class
  private
    FClasses: TObjectDictionary<string, TScopeClass>;
    /// <summary>Konstante (klein) → Klasse, die sie deklariert; '' wenn mehrere Klassen sie deklarieren.</summary>
    FConstOwners: TDictionary<string, string>;
    FUnitNames: TNameSet;
    /// <summary>Routinen, Konstanten und Variablen der Unit-Ebene (klein) mit ihrer Deklaration.</summary>
    FUnitValues: TDictionary<string, TSyntaxNode>;
    procedure AddClass(ADecl, ABody: TSyntaxNode; const AOuter: string);
    procedure AddMembers(AClass: TScopeClass);
    procedure AddUnitName(ANode: TSyntaxNode);
    procedure Scan(ANode: TSyntaxNode; const AOuter: string);
  public
    constructor Create(ARoot: TSyntaxNode);
    destructor Destroy; override;
    function FindClass(const AName: string; out AClass: TScopeClass): Boolean;
    /// <summary>Klasse zum Knoten ANode (ClassType, RecordType, ObjectType).</summary>
    function ClassOfNode(ANode: TSyntaxNode; out AClass: TScopeClass): Boolean;
    /// <summary>Deklariert eine Klasse der Datei eine Konstante?</summary>
    function HasConstants: Boolean;
    /// <summary>Klasse, die die Konstante AName deklariert; False ohne oder bei mehreren.</summary>
    function ConstOwner(const AName: string; out AOwner: string): Boolean;
    function IsUnitName(const AName: string): Boolean;
    /// <summary>Routine, Konstante oder Variable der Unit-Ebene namens AName; False ohne.</summary>
    function UnitValue(const AName: string; out ADeclaration: TSyntaxNode): Boolean;
    function HasUnitValues: Boolean;
    /// <summary>Klasse der Datei, in der die Kette von AClass die Datei verlässt: Name des ersten Vorfahren, den die
    /// Datei nicht deklariert; '' wenn die Kette in der Datei endet.</summary>
    function OutsideAncestor(const AClass: TScopeClass): string;
    /// <summary>Klasse der Kette von AClass in der Datei, die AName deklariert; nil ohne.</summary>
    function MemberOwner(const AClass: TScopeClass; const AName: string): TScopeClass;
    /// <summary>Hat AClass oder ein Vorfahr in der Datei (AInherited) ein Mitglied AName? AUnknown: Die Kette
    /// verlässt die Datei.</summary>
    function HasMember(const AClass: TScopeClass; const AName: string; AInherited: Boolean;
      out AUnknown: Boolean): Boolean;
    /// <summary>Ist AOwner AClass selbst, ein Vorfahr (AInherited) oder ein umgebender Typ?</summary>
    function Sees(const AClass: TScopeClass; const AOwner: string; AInherited: Boolean): Boolean;
    /// <summary>Ist AOwner ein Vorfahr von AClass in der Datei?</summary>
    function IsAncestor(const AClass: TScopeClass; const AOwner: string): Boolean;
  end;

/// <summary>Namen einer Liste "A, B" (klein) in ANames.</summary>
procedure AddNames(ANames: TNameSet; const AList: string);
var
  mName: string;
begin
  for mName in AList.Split([',']) do
  begin
    if Trim(mName) <> '' then
    begin
      ANames.AddOrSetValue(LowerCase(Trim(mName)), True);
    end;
  end;
end;

/// <summary>"System.Classes.TList&lt;T&gt;" → "TList".</summary>
function PlainTypeName(const AName: string): string;
begin
  Result := TRoutineSignatures.WithoutTypeParams(AName);
  Result := Copy(Result, LastDelimiter('.', Result) + 1, MaxInt);
end;

{ TScopeClass }

constructor TScopeClass.Create;
begin
  inherited Create;
  Members := TNameSet.Create;
  Constants := TNameSet.Create;
end;

destructor TScopeClass.Destroy;
begin
  Constants.Free;
  Members.Free;
  inherited;
end;

{ TScopeModel }

constructor TScopeModel.Create(ARoot: TSyntaxNode);
begin
  inherited Create;
  FClasses := TObjectDictionary<string, TScopeClass>.Create([doOwnsValues]);
  FConstOwners := TDictionary<string, string>.Create;
  FUnitNames := TNameSet.Create;
  FUnitValues := TDictionary<string, TSyntaxNode>.Create;
  Scan(ARoot, '');
end;

destructor TScopeModel.Destroy;
begin
  FUnitValues.Free;
  FUnitNames.Free;
  FConstOwners.Free;
  FClasses.Free;
  inherited;
end;

procedure TScopeModel.AddUnitName(ANode: TSyntaxNode);
var
  mName: string;
begin
  mName := ANode.Name;
  // Implementierungen von Methoden ("TKlasse.Machen") gehören nicht auf die Unit-Ebene.
  if (ANode.Kind = TSyntaxKind.RoutineDecl) and (Pos('.', mName) > 0) then
  begin
    Exit;
  end;
  AddNames(FUnitNames, TRoutineSignatures.WithoutTypeParams(mName));
  if (ANode.Kind <> TSyntaxKind.TypeDecl) and not FUnitValues.ContainsKey(LowerCase(mName)) and
    (Pos(',', mName) = 0) then
  begin
    FUnitValues.Add(LowerCase(mName), ANode);
  end;
end;

procedure TScopeModel.Scan(ANode: TSyntaxNode; const AOuter: string);
var
  mIndex: Integer;
  mChild, mBody: TSyntaxNode;
begin
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    mChild := ANode[mIndex];
    case mChild.Kind of
      TSyntaxKind.TypeDecl:
        begin
          if AOuter = '' then
          begin
            AddUnitName(mChild);
          end;
          mBody := mChild.FindChild(TSyntaxKind.ClassType);
          if mBody = nil then
          begin
            mBody := mChild.FindChild(TSyntaxKind.RecordType);
          end;
          if mBody = nil then
          begin
            mBody := mChild.FindChild(TSyntaxKind.ObjectType);
          end;
          if mBody <> nil then
          begin
            AddClass(mChild, mBody, AOuter);
          end;
        end;
      TSyntaxKind.ConstDecl, TSyntaxKind.VarDecl:
        if AOuter = '' then
        begin
          AddUnitName(mChild);
        end;
      TSyntaxKind.RoutineDecl:
        // Rümpfe haben eigene, lokale Namen.
        AddUnitName(mChild);
    else
      Scan(mChild, AOuter);
    end;
  end;
end;

procedure TScopeModel.AddClass(ADecl, ABody: TSyntaxNode; const AOuter: string);
var
  mClass: TScopeClass;
  mAncestor: TSyntaxNode;
  mKey: string;
begin
  mClass := TScopeClass.Create;
  mClass.ShortName := TRoutineSignatures.WithoutTypeParams(ADecl.Name);
  mClass.Outer := AOuter;
  mClass.Name := mClass.ShortName;
  if AOuter <> '' then
  begin
    mClass.Name := AOuter + '.' + mClass.ShortName;
  end;
  mClass.Node := ABody;
  mAncestor := ABody.FindChild(TSyntaxKind.TypeReference);
  if mAncestor <> nil then
  begin
    mClass.Ancestor := PlainTypeName(mAncestor.Name);
  end;
  mKey := LowerCase(mClass.Name);
  if FClasses.ContainsKey(mKey) then
  begin
    // Bedingte Doppeldeklaration ({$IFDEF}): die erste zählt.
    mClass.Free;
    Exit;
  end;
  FClasses.Add(mKey, mClass);
  AddMembers(mClass);
  Scan(ABody, mClass.Name);
end;

procedure TScopeModel.AddMembers(AClass: TScopeClass);

  procedure Visit(ANode: TSyntaxNode);
  var
    mIndex: Integer;
    mChild: TSyntaxNode;
    mOwner: string;
  begin
    for mIndex := 0 to ANode.ChildCount - 1 do
    begin
      mChild := ANode[mIndex];
      case mChild.Kind of
        TSyntaxKind.TypeDecl:
          AddNames(AClass.Members, TRoutineSignatures.WithoutTypeParams(mChild.Name));
        TSyntaxKind.ConstDecl:
          begin
            AddNames(AClass.Members, mChild.Name);
            AddNames(AClass.Constants, mChild.Name);
            if FConstOwners.TryGetValue(LowerCase(mChild.Name), mOwner) then
            begin
              FConstOwners[LowerCase(mChild.Name)] := '';
            end
            else
            begin
              FConstOwners.Add(LowerCase(mChild.Name), AClass.Name);
            end;
          end;
        TSyntaxKind.Field, TSyntaxKind.VarDecl, TSyntaxKind.PropertyDecl, TSyntaxKind.RoutineHeader,
        TSyntaxKind.RoutineDecl:
          AddNames(AClass.Members, mChild.Name);
        TSyntaxKind.Visibility, TSyntaxKind.ConstSection, TSyntaxKind.VarSection, TSyntaxKind.TypeSection,
        TSyntaxKind.VariantPart:
          Visit(mChild);
      else
        // Typverweise, Attribute und Ausdrücke deklarieren nichts.
      end;
    end;
  end;

begin
  Visit(AClass.Node);
end;

function TScopeModel.FindClass(const AName: string; out AClass: TScopeClass): Boolean;
begin
  Result := FClasses.TryGetValue(LowerCase(TRoutineSignatures.WithoutTypeParams(AName)), AClass);
end;

function TScopeModel.ClassOfNode(ANode: TSyntaxNode; out AClass: TScopeClass): Boolean;
var
  mClass: TScopeClass;
begin
  for mClass in FClasses.Values do
  begin
    if mClass.Node = ANode then
    begin
      AClass := mClass;
      Exit(True);
    end;
  end;
  AClass := nil;
  Result := False;
end;

function TScopeModel.HasConstants: Boolean;
begin
  Result := FConstOwners.Count > 0;
end;

function TScopeModel.ConstOwner(const AName: string; out AOwner: string): Boolean;
begin
  Result := FConstOwners.TryGetValue(LowerCase(AName), AOwner) and (AOwner <> '');
end;

function TScopeModel.IsUnitName(const AName: string): Boolean;
begin
  Result := FUnitNames.ContainsKey(LowerCase(AName));
end;

function TScopeModel.UnitValue(const AName: string; out ADeclaration: TSyntaxNode): Boolean;
begin
  Result := FUnitValues.TryGetValue(LowerCase(AName), ADeclaration);
end;

function TScopeModel.HasUnitValues: Boolean;
begin
  Result := FUnitValues.Count > 0;
end;

/// <summary>Klasse der Datei namens AName, gesucht von AFrom aus nach außen (verschachtelte Typen zuerst).</summary>
function FindFrom(AModel: TScopeModel; const AFrom: TScopeClass; const AName: string;
  out AClass: TScopeClass): Boolean;
var
  mOuter: string;
begin
  mOuter := AFrom.Outer;
  while mOuter <> '' do
  begin
    if AModel.FindClass(mOuter + '.' + AName, AClass) then
    begin
      Exit(True);
    end;
    mOuter := Copy(mOuter, 1, LastDelimiter('.', mOuter) - 1);
  end;
  Result := AModel.FindClass(AName, AClass);
end;

function TScopeModel.HasMember(const AClass: TScopeClass; const AName: string; AInherited: Boolean;
  out AUnknown: Boolean): Boolean;
var
  mCurrent, mNext: TScopeClass;
  mDepth: Integer;
begin
  AUnknown := False;
  mCurrent := AClass;
  for mDepth := 0 to 64 do
  begin
    if mCurrent.Members.ContainsKey(LowerCase(AName)) then
    begin
      Exit(True);
    end;
    if not AInherited or (mCurrent.Ancestor = '') or SameText(mCurrent.Ancestor, 'TObject') then
    begin
      Break;
    end;
    if not FindFrom(Self, mCurrent, mCurrent.Ancestor, mNext) then
    begin
      AUnknown := True;
      Break;
    end;
    mCurrent := mNext;
  end;
  Result := False;
end;

function TScopeModel.OutsideAncestor(const AClass: TScopeClass): string;
var
  mCurrent, mNext: TScopeClass;
  mDepth: Integer;
begin
  Result := '';
  mCurrent := AClass;
  for mDepth := 0 to 64 do
  begin
    if mCurrent.Ancestor = '' then
    begin
      Exit;
    end;
    if not FindFrom(Self, mCurrent, mCurrent.Ancestor, mNext) then
    begin
      Exit(mCurrent.Ancestor);
    end;
    mCurrent := mNext;
  end;
end;

function TScopeModel.MemberOwner(const AClass: TScopeClass; const AName: string): TScopeClass;
var
  mNext: TScopeClass;
  mDepth: Integer;
begin
  Result := AClass;
  for mDepth := 0 to 64 do
  begin
    if Result.Members.ContainsKey(LowerCase(AName)) then
    begin
      Exit;
    end;
    if (Result.Ancestor = '') or not FindFrom(Self, Result, Result.Ancestor, mNext) then
    begin
      Break;
    end;
    Result := mNext;
  end;
  Result := nil;
end;

function TScopeModel.IsAncestor(const AClass: TScopeClass; const AOwner: string): Boolean;
var
  mCurrent, mNext: TScopeClass;
  mDepth: Integer;
begin
  Result := False;
  mCurrent := AClass;
  for mDepth := 0 to 64 do
  begin
    if (mCurrent.Ancestor = '') or not FindFrom(Self, mCurrent, mCurrent.Ancestor, mNext) then
    begin
      Exit;
    end;
    if SameText(mNext.Name, AOwner) then
    begin
      Exit(True);
    end;
    mCurrent := mNext;
  end;
end;

function TScopeModel.Sees(const AClass: TScopeClass; const AOwner: string; AInherited: Boolean): Boolean;
var
  mOuter: TScopeClass;
begin
  Result := SameText(AClass.Name, AOwner) or (AInherited and IsAncestor(AClass, AOwner));
  // Ein verschachtelter Typ sieht die Konstanten der umgebenden Typen samt deren Vorfahren.
  if not Result and (AClass.Outer <> '') and FindClass(AClass.Outer, mOuter) then
  begin
    Result := Sees(mOuter, AOwner, True);
  end;
end;

{ TClassConstantUnqualifiedRule }

function TClassConstantUnqualifiedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cClassConstantUnqualifiedRuleId, TRuleSeverity.Error,
    cTexts[TScopeTrapText.ConstTitle].Text);
end;

type
  /// <summary>Prüft die Bezeichner einer Methode bzw. einer Klassendeklaration.</summary>
  TConstantScan = class
  private
    FModel: TScopeModel;
    FReport: IRuleReport;
    FIndex: ISymbolIndex;
    FUnitName: string;
    /// <summary>Kennt der Index AName außerhalb dieser Datei? Dann kann ein unbekannter Vorfahr ihn deklarieren.
    /// </summary>
    function KnownElsewhere(const AName: string): Boolean;
    procedure CheckIdentifier(AIdent: TSyntaxNode; const AClass: TScopeClass; ADeclaration: Boolean;
      ALocals: TNameSet);
    procedure CheckNodes(ARoot: TSyntaxNode; const AClass: TScopeClass; ADeclaration: Boolean; ALocals: TNameSet);
    procedure CheckRoutine(ARoutine: TSyntaxNode);
    procedure CheckDeclaration(const AClass: TScopeClass);
  public
    constructor Create(AModel: TScopeModel; const AReport: IRuleReport; const AIndex: ISymbolIndex;
      const AUnitName: string);
    procedure Run(ARoot: TSyntaxNode);
  end;

constructor TConstantScan.Create(AModel: TScopeModel; const AReport: IRuleReport; const AIndex: ISymbolIndex;
  const AUnitName: string);
begin
  inherited Create;
  FModel := AModel;
  FReport := AReport;
  FIndex := AIndex;
  FUnitName := AUnitName;
end;

function TConstantScan.KnownElsewhere(const AName: string): Boolean;
var
  mLocation: TSymbolLocation;
begin
  Result := False;
  if FIndex = nil then
  begin
    Exit;
  end;
  for mLocation in FIndex.FindSymbols(AName) do
  begin
    if not SameText(mLocation.UnitName, FUnitName) then
    begin
      Exit(True);
    end;
  end;
end;

procedure TConstantScan.CheckIdentifier(AIdent: TSyntaxNode; const AClass: TScopeClass; ADeclaration: Boolean;
  ALocals: TNameSet);
var
  mName, mOwner, mMessage: string;
  mUnknown: Boolean;
  mFix: TRuleFix;
  mText: TScopeTrapText;
begin
  mName := AIdent.Name;
  if (ALocals <> nil) and ALocals.ContainsKey(LowerCase(mName)) or not FModel.ConstOwner(mName, mOwner) or
    FModel.Sees(AClass, mOwner, not ADeclaration) or FModel.IsUnitName(mName) then
  begin
    Exit;
  end;
  // Ein Vorfahr außerhalb der Datei kann den Namen deklarieren, wenn der Index ihn anderswo kennt.
  if FModel.HasMember(AClass, mName, not ADeclaration, mUnknown) then
  begin
    Exit;
  end;
  if mUnknown and KnownElsewhere(mName) then
  begin
    Exit;
  end;
  mText := TScopeTrapText.ConstForeign;
  if ADeclaration and FModel.IsAncestor(AClass, mOwner) then
  begin
    mText := TScopeTrapText.ConstInherited;
  end;
  mMessage := cTexts[mText].Fmt([mName, mOwner, AClass.Name]);
  mFix := TRuleFix.Create(cTexts[TScopeTrapText.ConstFix].Fmt([mOwner, mName]),
    [TTextEdit.Create(TTextRange.Create(AIdent.StartPos, AIdent.StartPos), mOwner + '.')], True);
  FReport.Add(TTextRange.Create(AIdent.StartPos, AIdent.EndPos), mMessage, TRuleConfidence.High, [mFix]);
end;

procedure TConstantScan.CheckNodes(ARoot: TSyntaxNode; const AClass: TScopeClass; ADeclaration: Boolean;
  ALocals: TNameSet);
begin
  ARoot.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      // with kann jeden Namen umleiten; verschachtelte Typen prüft ihre eigene Deklaration.
      Result := not (ANode.Kind in [TSyntaxKind.WithStatement, TSyntaxKind.ClassType, TSyntaxKind.RecordType,
        TSyntaxKind.ObjectType]) or (ANode = ARoot);
      if ANode.Kind = TSyntaxKind.Identifier then
      begin
        CheckIdentifier(ANode, AClass, ADeclaration, ALocals);
      end;
    end);
end;

/// <summary>Lokale Namen der Routine ARoutine samt verschachtelter Routinen.</summary>
procedure CollectLocals(ARoutine: TSyntaxNode; ALocals: TNameSet);
begin
  ARoutine.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := True;
      case ANode.Kind of
        TSyntaxKind.Parameter, TSyntaxKind.VarDecl, TSyntaxKind.ConstDecl, TSyntaxKind.InlineVar,
        TSyntaxKind.InlineConst, TSyntaxKind.TypeDecl, TSyntaxKind.LabelSection:
          AddNames(ALocals, ANode.Name);
        TSyntaxKind.RoutineDecl:
          if ANode <> ARoutine then
          begin
            AddNames(ALocals, ANode.Name);
          end;
      else
        // Übrige Knoten deklarieren nichts.
      end;
    end);
end;

procedure TConstantScan.CheckRoutine(ARoutine: TSyntaxNode);
var
  mClassName: string;
  mClass: TScopeClass;
  mLocals: TNameSet;
  mIndex: Integer;
begin
  mClassName := TRoutineSignatures.WithoutTypeParams(ARoutine.Name);
  mClassName := Copy(mClassName, 1, LastDelimiter('.', mClassName) - 1);
  if (mClassName = '') or not FModel.FindClass(mClassName, mClass) then
  begin
    Exit;
  end;
  mLocals := TNameSet.Create;
  try
    CollectLocals(ARoutine, mLocals);
    for mIndex := 0 to ARoutine.ChildCount - 1 do
    begin
      if ARoutine[mIndex].Kind <> TSyntaxKind.RoutineHeader then
      begin
        CheckNodes(ARoutine[mIndex], mClass, False, mLocals);
      end;
    end;
  finally
    mLocals.Free;
  end;
end;

procedure TConstantScan.CheckDeclaration(const AClass: TScopeClass);
begin
  CheckNodes(AClass.Node, AClass, True, nil);
end;

procedure TConstantScan.Run(ARoot: TSyntaxNode);
var
  mRoutines, mClasses: TList<TSyntaxNode>;
  mNode: TSyntaxNode;
  mClass: TScopeClass;
begin
  mRoutines := TList<TSyntaxNode>.Create;
  mClasses := TList<TSyntaxNode>.Create;
  try
    ARoot.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        Result := ANode.Kind <> TSyntaxKind.RoutineDecl;
        if not Result and (Pos('.', ANode.Name) > 0) then
        begin
          mRoutines.Add(ANode);
        end;
      end);
    for mNode in mRoutines do
    begin
      CheckRoutine(mNode);
    end;
    ARoot.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        Result := ANode.Kind <> TSyntaxKind.RoutineDecl;
        if ANode.Kind in [TSyntaxKind.ClassType, TSyntaxKind.RecordType, TSyntaxKind.ObjectType] then
        begin
          mClasses.Add(ANode);
        end;
      end);
    for mNode in mClasses do
    begin
      if FModel.ClassOfNode(mNode, mClass) then
      begin
        CheckDeclaration(mClass);
      end;
    end;
  finally
    mClasses.Free;
    mRoutines.Free;
  end;
end;

procedure TClassConstantUnqualifiedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mModel: TScopeModel;
  mScan: TConstantScan;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not ContainsText(AContext.Text, 'const') then
  begin
    Exit;
  end;
  mModel := TScopeModel.Create(AContext.Tree.Root);
  try
    if not mModel.HasConstants then
    begin
      Exit;
    end;
    mScan := TConstantScan.Create(mModel, AReport, AContext.Index, AContext.UnitName);
    try
      mScan.Run(AContext.Tree.Root);
    finally
      mScan.Free;
    end;
  finally
    mModel.Free;
  end;
end;

{ TEnumHidesKeywordRule }

function TEnumHidesKeywordRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cEnumHidesKeywordRuleId, TRuleSeverity.Warning,
    cTexts[TScopeTrapText.EnumTitle].Text);
end;

/// <summary>Gilt {$SCOPEDENUMS ON} am Offset AOffset? Die letzte Direktive davor entscheidet, ohne gilt OFF.
/// </summary>
function ScopedAt(const ATokens: TArray<TPascalToken>; AOffset: Integer): Boolean;
var
  mToken: TPascalToken;
  mText: string;
begin
  Result := False;
  for mToken in ATokens do
  begin
    if mToken.Offset >= AOffset then
    begin
      Break;
    end;
    if mToken.Kind = TPascalTokenKind.Directive then
    begin
      mText := UpperCase(StringReplace(mToken.Text, ' ', '', [rfReplaceAll]));
      if ContainsStr(mText, '$' + cScopedEnumsDirective) then
      begin
        Result := ContainsStr(mText, cScopedEnumsDirective + 'ON') or ContainsStr(mText, cScopedEnumsDirective + '+');
      end;
    end;
  end;
end;

procedure TEnumHidesKeywordRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TArray<TPascalToken>;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  AContext.Tree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      mIndex: Integer;
      mValue: TSyntaxNode;
    begin
      Result := ANode.Kind <> TSyntaxKind.EnumType;
      if Result or (ANode.Parent = nil) or (ANode.Parent.Kind <> TSyntaxKind.TypeDecl) then
      begin
        Exit;
      end;
      for mIndex := 0 to ANode.ChildCount - 1 do
      begin
        mValue := ANode[mIndex];
        if (mValue.Kind = TSyntaxKind.Identifier) and MatchText(mValue.Name, cHiddenKeywords) and
          not ScopedAt(mTokens, ANode.StartOffset) then
        begin
          AReport.Add(TTextRange.Create(mValue.StartPos, mValue.EndPos), cTexts[TScopeTrapText.EnumMessage].Fmt(
            [mValue.Name, ANode.Parent.Name]), TRuleConfidence.High);
        end;
      end;
    end);
end;

{ TInlineReferenceTypeRule }

function TInlineReferenceTypeRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cInlineReferenceTypeRuleId, TRuleSeverity.Error,
    cTexts[TScopeTrapText.ReferenceTitle].Text);
end;

procedure TInlineReferenceTypeRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not ContainsText(AContext.Text, 'reference') then
  begin
    Exit;
  end;
  AContext.Tree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      mOwner: TSyntaxNode;
    begin
      Result := True;
      if (ANode.Kind <> TSyntaxKind.ProcedureType) or not SameText(ANode.Name, 'reference') or
        (ANode.Parent = nil) then
      begin
        Exit;
      end;
      mOwner := ANode.Parent;
      if mOwner.Kind in [TSyntaxKind.Field, TSyntaxKind.VarDecl, TSyntaxKind.InlineVar] then
      begin
        AReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos), cTexts[TScopeTrapText.ReferenceMessage].Fmt(
          [mOwner.Name]), TRuleConfidence.High);
      end;
    end);
end;

{ TMemberHidesUnitSymbolRule }

function TMemberHidesUnitSymbolRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cMemberHidesUnitSymbolRuleId, TRuleSeverity.Warning,
    cTexts[TScopeTrapText.HiddenTitle].Text);
end;

type
  /// <summary>Sucht in Methoden Namen der Unit, die ein Mitglied der Klasse verdeckt.</summary>
  THiddenScan = class
  private
    FModel: TScopeModel;
    FReport: IRuleReport;
    FIndex: ISymbolIndex;
    FUnitName: string;
    /// <summary>Klasse des Index namens AClassName außerhalb dieser Unit; False ohne oder bei mehreren.</summary>
    function IndexClass(const AClassName: string; out ASymbol: TIndexSymbol): Boolean;
    /// <summary>Klasse der Kette ab AClassName (im Index), die AName deklariert; '' ohne.</summary>
    function IndexOwner(const AClassName, AName: string): string;
    /// <summary>Klasse, deren Mitglied AName in Methoden von AClass gilt; '' ohne.</summary>
    function OwnerOf(const AClass: TScopeClass; const AName: string): string;
    procedure CheckRoutine(ARoutine: TSyntaxNode);
  public
    constructor Create(AModel: TScopeModel; const AReport: IRuleReport; const AIndex: ISymbolIndex;
      const AUnitName: string);
    procedure Run(ARoot: TSyntaxNode);
  end;

/// <summary>Vorfahr aus der Signatur "TFoo = class(TBasis, IFoo)"; '' ohne.</summary>
function AncestorOfSignature(const ASignature: string): string;
var
  mOpen, mClose: Integer;
begin
  Result := '';
  mOpen := Pos('(', ASignature);
  mClose := Pos(')', ASignature);
  if (mOpen = 0) or (mClose < mOpen) then
  begin
    Exit;
  end;
  Result := Trim(Copy(ASignature, mOpen + 1, mClose - mOpen - 1));
  if Pos(',', Result) > 0 then
  begin
    Result := Trim(Copy(Result, 1, Pos(',', Result) - 1));
  end;
  Result := PlainTypeName(Result);
end;

constructor THiddenScan.Create(AModel: TScopeModel; const AReport: IRuleReport; const AIndex: ISymbolIndex;
  const AUnitName: string);
begin
  inherited Create;
  FModel := AModel;
  FReport := AReport;
  FIndex := AIndex;
  FUnitName := AUnitName;
end;

function THiddenScan.IndexClass(const AClassName: string; out ASymbol: TIndexSymbol): Boolean;
var
  mLocation: TSymbolLocation;
  mCount: Integer;
begin
  mCount := 0;
  ASymbol := Default(TIndexSymbol);
  for mLocation in FIndex.FindSymbols(AClassName) do
  begin
    if (mLocation.Symbol.Kind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.RecordType]) and
      (mLocation.Symbol.Container = '') and not SameText(mLocation.UnitName, FUnitName) then
    begin
      ASymbol := mLocation.Symbol;
      Inc(mCount);
    end;
  end;
  Result := mCount = 1;
end;

function THiddenScan.IndexOwner(const AClassName, AName: string): string;
var
  mClassName: string;
  mClass: TIndexSymbol;
  mLocation: TSymbolLocation;
  mDepth: Integer;
begin
  Result := '';
  mClassName := AClassName;
  for mDepth := 0 to 64 do
  begin
    if (mClassName = '') or SameText(mClassName, 'TObject') or not IndexClass(mClassName, mClass) then
    begin
      Exit;
    end;
    for mLocation in FIndex.FindSymbols(AName) do
    begin
      if SameText(PlainTypeName(mLocation.Symbol.Container), mClassName) and
        not SameText(mLocation.UnitName, FUnitName) then
      begin
        Exit(mClassName);
      end;
    end;
    mClassName := AncestorOfSignature(mClass.Signature);
  end;
end;

function THiddenScan.OwnerOf(const AClass: TScopeClass; const AName: string): string;
var
  mOwner: TScopeClass;
begin
  mOwner := FModel.MemberOwner(AClass, AName);
  if mOwner <> nil then
  begin
    Exit(mOwner.Name);
  end;
  Result := '';
  if FIndex <> nil then
  begin
    Result := IndexOwner(FModel.OutsideAncestor(AClass), AName);
  end;
end;

procedure THiddenScan.CheckRoutine(ARoutine: TSyntaxNode);
var
  mClassName: string;
  mClass: TScopeClass;
  mLocals: TNameSet;
begin
  mClassName := TRoutineSignatures.WithoutTypeParams(ARoutine.Name);
  mClassName := Copy(mClassName, 1, LastDelimiter('.', mClassName) - 1);
  if (mClassName = '') or not FModel.FindClass(mClassName, mClass) then
  begin
    Exit;
  end;
  mLocals := TNameSet.Create;
  try
    CollectLocals(ARoutine, mLocals);
    ARoutine.Walk(
      function(ANode: TSyntaxNode): Boolean
      var
        mDeclaration: TSyntaxNode;
        mOwner: string;
        mFix: TRuleFix;
      begin
        Result := ANode.Kind <> TSyntaxKind.WithStatement;
        if (ANode.Kind <> TSyntaxKind.Identifier) or mLocals.ContainsKey(LowerCase(ANode.Name)) or
          not FModel.UnitValue(ANode.Name, mDeclaration) then
        begin
          Exit;
        end;
        // Ein eigenes Mitglied der Klasse ist gewollt; die Falle ist das geerbte.
        mOwner := OwnerOf(mClass, ANode.Name);
        if (mOwner = '') or SameText(mOwner, mClass.Name) then
        begin
          Exit;
        end;
        mFix := TRuleFix.Create(cTexts[TScopeTrapText.HiddenFix].Fmt([FUnitName, ANode.Name]),
          [TTextEdit.Create(TTextRange.Create(ANode.StartPos, ANode.StartPos), FUnitName + '.')]);
        FReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos), cTexts[TScopeTrapText.HiddenMessage].Fmt(
          [ANode.Name, mClass.Name, mOwner, mDeclaration.StartPos.Line + 1, FUnitName]), TRuleConfidence.High,
          [mFix]);
      end);
  finally
    mLocals.Free;
  end;
end;

procedure THiddenScan.Run(ARoot: TSyntaxNode);
begin
  ARoot.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := ANode.Kind <> TSyntaxKind.RoutineDecl;
      if not Result and (Pos('.', ANode.Name) > 0) then
      begin
        CheckRoutine(ANode);
      end;
    end);
end;

procedure TMemberHidesUnitSymbolRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mModel: TScopeModel;
  mScan: THiddenScan;
  mUnitName: string;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  // Der Name aus dem Kopf der Unit ist der, den die Korrektur davor setzt.
  mUnitName := AContext.Tree.Root.Name;
  if mUnitName = '' then
  begin
    mUnitName := AContext.UnitName;
  end;
  if mUnitName = '' then
  begin
    Exit;
  end;
  mModel := TScopeModel.Create(AContext.Tree.Root);
  try
    if not mModel.HasUnitValues then
    begin
      Exit;
    end;
    mScan := THiddenScan.Create(mModel, AReport, AContext.Index, mUnitName);
    try
      mScan.Run(AContext.Tree.Root);
    finally
      mScan.Free;
    end;
  finally
    mModel.Free;
  end;
end;

procedure RegisterCompilerTrapScopeRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TClassConstantUnqualifiedRule.Create);
  ARegistry.Register(TEnumHidesKeywordRule.Create);
  ARegistry.Register(TInlineReferenceTypeRule.Create);
  ARegistry.Register(TMemberHidesUnitSymbolRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.CompilerTraps.Scopes', cTexts);

end.
