unit Atlas.Common.Rules.Builtin.Testing.AreEqual;

// Regel aus Atlas.Common.Rules.Builtin.Testing (Gruppe Compiler vorab, #1937); angemeldet wird sie dort:
//   dunitx-areequal-length  Assert.AreEqual bzw. Assert.AreNotEqual mit einer Ganzzahl auf der einen und einem
//                           NativeInt auf der anderen Seite: Length, High oder Low eines dynamischen Arrays (ab
//                           Delphi 12 NativeInt) oder ein Ausdruck, dessen Typ sicher NativeInt bzw. NativeUInt ist
//                           (TList<T>.Count mit der RTL im Index). Keine der Überladungen Integer, Int64, Double …
//                           passt eindeutig, Delphi fällt auf AreEqual<T> zurück und kann T nicht ableiten (E2532).
//                           FPC übersetzt den Aufruf, deshalb fällt der Fehler erst beim Bau mit Delphi auf.
//                           Strings (Length gibt Integer), statische Arrays und Ausdrücke unbekannten Typs bleiben
//                           still, ebenso eine bekannte Delphi-Version vor 12. Korrektur: Integer(...) um die
//                           NativeInt-Seite, sicher (auch „alle in der Datei“).

interface

uses
  Atlas.Common.Rules.Contract;

const
  cDUnitXAreEqualLengthRuleId = 'dunitx-areequal-length';

type
  TDUnitXAreEqualLengthRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Rules.TypedScope,
  Atlas.Common.Semantics.ExpressionTypes,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TAreEqualText = (Title, Ambiguous, WrapInteger);

const
  cTexts: array[TAreEqualText] of TAtlasText = (
    (De: 'Assert.AreEqual mit Ganzzahl und NativeInt'; En: 'Assert.AreEqual with integer and NativeInt'),
    (De: '%s vergleicht eine Ganzzahl mit %s (NativeInt): Keine Überladung passt eindeutig, AreEqual<T> kann T ' +
      'nicht ableiten (wie E2532 unter Delphi). Integer(...) darum setzen.';
     En: '%s compares an integer with %s (NativeInt): no overload fits unambiguously, AreEqual<T> cannot infer T ' +
      '(like E2532 in Delphi). Wrap it in Integer(...).'),
    (De: 'Integer(...) darum setzen'; En: 'Wrap in Integer(...)'));

{$SCOPEDENUMS OFF}

const
  cAssertMethods: array[0..1] of string = ('Assert.AreEqual', 'Assert.AreNotEqual');
  cArrayIntrinsics: array[0..2] of string = ('Length', 'High', 'Low');
  cNativeTypes: array[0..1] of string = ('NativeInt', 'NativeUInt');
  cIntegerTypes: array[0..7] of string = ('Integer', 'Cardinal', 'LongInt', 'LongWord', 'SmallInt', 'Word',
    'ShortInt', 'Byte');
  // Delphi 12 (BDS 23.0): Length, High und Low dynamischer Arrays liefern NativeInt.
  cNativeLengthVersion = 23;

type
  /// <summary>Art eines Arguments von Assert.AreEqual für die Prüfung.</summary>
  TArgumentKind = (Unknown, Integer_, Native);

  /// <summary>Eine Prüfung einer Datei.</summary>
  TAreEqualCheck = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FScope: TTypedScope;
    FTypes: TExpressionTypes;
    function TypeNameOf(ANode: TSyntaxNode): string;
    function IsDynamicArray(ANode: TSyntaxNode): Boolean;
    function KindOf(ANode: TSyntaxNode): TArgumentKind;
    procedure CheckCall(ACall: TSyntaxNode);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    destructor Destroy; override;
    procedure Run;
  end;

/// <summary>Hauptversion aus "23.0"; 0, wenn unbekannt.</summary>
function MajorVersion(const AVersion: string): Integer;
begin
  Result := StrToIntDef(Copy(AVersion, 1, Pos('.', AVersion + '.') - 1), 0);
end;

{ TAreEqualCheck }

constructor TAreEqualCheck.Create(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mOptions: TExpressionTypeOptions;
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FScope := TTypedScope.Create(AContext);
  mOptions := TExpressionTypeOptions.Default;
  mOptions.Conversions := False;
  mOptions.ConstValue := False;
  FTypes := TExpressionTypes.Create(FScope.Resolver, AContext.Tree, FScope.FileName, AContext.Text, AContext.Index,
    mOptions);
end;

destructor TAreEqualCheck.Destroy;
begin
  FTypes.Free;
  FScope.Free;
  inherited;
end;

function TAreEqualCheck.TypeNameOf(ANode: TSyntaxNode): string;
var
  mInfo: TExpressionTypeInfo;
begin
  mInfo := FTypes.Describe(ANode);
  Result := '';
  if mInfo.Found then
  begin
    Result := mInfo.TypeName;
    if mInfo.BaseName <> '' then
    begin
      Result := mInfo.BaseName;
    end;
  end;
end;

function TAreEqualCheck.IsDynamicArray(ANode: TSyntaxNode): Boolean;
var
  mType: string;
begin
  mType := StringReplace(TypeNameOf(ANode), ' ', '', [rfReplaceAll]);
  // Ohne System im Index nennt die Namensauflösung TArray<T> nur TArray.
  Result := MatchText(mType, ['TArray', 'System.TArray']) or StartsText('TArray<', mType) or
    StartsText('System.TArray<', mType) or StartsText('arrayof', mType);
end;

function TAreEqualCheck.KindOf(ANode: TSyntaxNode): TArgumentKind;
var
  mNode: TSyntaxNode;
  mType: string;
begin
  Result := TArgumentKind.Unknown;
  mNode := Unwrapped(ANode);
  if (mNode.Kind = TSyntaxKind.Literal) and (mNode.Name <> '') and CharInSet(mNode.Name[1], ['0'..'9', '$']) and
    (Pos('.', mNode.Name) = 0) and not ContainsText(mNode.Name, 'e') then
  begin
    Exit(TArgumentKind.Integer_);
  end;
  // Length(FListe), High(Werte): dynamisches Array ab Delphi 12 NativeInt, String Integer.
  if (mNode.Kind = TSyntaxKind.Call) and (mNode.ChildCount = 2) and (mNode[0].Kind = TSyntaxKind.Identifier) and
    MatchText(mNode[0].Name, cArrayIntrinsics) then
  begin
    if IsDynamicArray(mNode[1]) then
    begin
      Result := TArgumentKind.Native;
    end;
    Exit;
  end;
  mType := TypeNameOf(mNode);
  if MatchText(mType, cNativeTypes) or MatchText(mType, ['System.NativeInt', 'System.NativeUInt']) then
  begin
    Result := TArgumentKind.Native;
  end
  else if MatchText(mType, cIntegerTypes) then
  begin
    Result := TArgumentKind.Integer_;
  end;
end;

procedure TAreEqualCheck.CheckCall(ACall: TSyntaxNode);
var
  mLeft, mRight: TArgumentKind;
  mNative: TSyntaxNode;
  mFix: TRuleFix;
  mText: string;
begin
  // Mit Typargument (AreEqual<Integer>) ist T bekannt.
  if (ACall.ChildCount < 3) or not (ACall[0].Kind in [TSyntaxKind.MemberAccess, TSyntaxKind.Identifier]) or
    not MatchText(StringReplace(FScope.Text(ACall[0]), ' ', '', [rfReplaceAll]), cAssertMethods) or (ACall[0].FindChild(TSyntaxKind.GenericArgs) <> nil) or
    (ACall.FindChild(TSyntaxKind.GenericArgs) <> nil) then
  begin
    Exit;
  end;
  mLeft := KindOf(ACall[1]);
  mRight := KindOf(ACall[2]);
  if (mLeft = TArgumentKind.Native) and (mRight = TArgumentKind.Integer_) then
  begin
    mNative := ACall[1];
  end
  else if (mLeft = TArgumentKind.Integer_) and (mRight = TArgumentKind.Native) then
  begin
    mNative := ACall[2];
  end
  else
  begin
    Exit;
  end;
  mText := FScope.Text(mNative);
  mFix := TRuleFix.Create(cTexts[TAreEqualText.WrapInteger].Text, [TTextEdit.Create(TTextRange.Create(
    mNative.StartPos, mNative.EndPos), 'Integer(' + mText + ')')], True);
  FReport.Add(TTextRange.Create(mNative.StartPos, mNative.EndPos), cTexts[TAreEqualText.Ambiguous].Fmt(
    [StringReplace(FScope.Text(ACall[0]), ' ', '', [rfReplaceAll]), mText]), TRuleConfidence.High, [mFix]);
end;

procedure TAreEqualCheck.Run;
var
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  // Iterativ (Bericht M1).
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(FContext.Tree.Root);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if mNode.Kind = TSyntaxKind.Call then
      begin
        CheckCall(mNode);
      end;
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        mPending.Push(mNode[mIndex]);
      end;
    end;
  finally
    mPending.Free;
  end;
end;

{ TDUnitXAreEqualLengthRule }

function TDUnitXAreEqualLengthRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cDUnitXAreEqualLengthRuleId, TRuleSeverity.Error, cTexts[TAreEqualText.Title].Text);
end;

procedure TDUnitXAreEqualLengthRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mCheck: TAreEqualCheck;
  mMajor: Integer;
begin
  mMajor := MajorVersion(AContext.DelphiVersion);
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or ((mMajor > 0) and (mMajor < cNativeLengthVersion)) or
    not ContainsText(AContext.Text, 'Assert.Are') then
  begin
    Exit;
  end;
  mCheck := TAreEqualCheck.Create(AContext, AReport);
  try
    mCheck.Run;
  finally
    mCheck.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Testing.AreEqual', cTexts);

end.
