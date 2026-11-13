unit Atlas.Common.Rules.Builtin.Testing.TearDown;

// Regel aus Atlas.Common.Rules.Builtin.Testing (#1781); angemeldet wird sie dort. Nur in Testunits:
//   dunitx-setup-not-torn-down  Feld einer Testklasse, dem die [Setup]-Methode (bzw. [SetupFixture]) ein Objekt
//                               zuweist (TFake.Create …), das die passende [TearDown]-Methode (bzw.
//                               [TearDownFixture]) weder mit Free, FreeAndNil, DisposeOf oder Destroy freigibt noch
//                               auf nil setzt: Jeder Test leckt das Objekt. Methoden derselben Klasse, die TearDown
//                               direkt aufruft, zählen mit (eine Ebene). Still bleiben Felder vom Interfacetyp
//                               (Referenzzählung) und Objekte mit Besitzer (TButton.Create(FForm)).
//                               Mit der Option managedFields (Vorgabe an) auch string- und dynamische Array-Felder,
//                               die Setup belegt und TearDown nicht leert: Der Leckmonitor von DUnitX zählt sie dem
//                               Test zu.
//                               Ohne TearDown-Methode eine Meldung am Setup für alle Felder.
//                               Korrektur: FreeAndNil(FFeld); (ohne SysUtils FFeld.Free; FFeld := nil;) bzw.
//                               FFeld := ''; oder FFeld := nil; am Ende von TearDown; ohne TearDown legt sie die
//                               Methode samt Attribut und Deklaration an.

interface

uses
  Atlas.Common.Rules.Contract;

const
  cDUnitXSetupNotTornDownRuleId = 'dunitx-setup-not-torn-down';

type
  TDUnitXSetupNotTornDownRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Text.Lines,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.TypedScope,
  Atlas.Common.Rules.Builtin.Testing.Classes,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TTearDownText = (Title, NotFreed, NotCleared, NoTearDown, ReleaseIn, CreateTearDown);

  /// <summary>Art eines Felds der Testklasse für die Prüfung.</summary>
  TFieldKind = (Other, Object_, String_, Array_);

const
  cTexts: array[TTearDownText] of TAtlasText = (
    (De: 'Feld im Setup erzeugt, im TearDown nicht freigegeben'; En: 'Field created in Setup, not freed in TearDown'),
    (De: '%s wird in %s erzeugt, aber in %s nicht freigegeben: Jeder Test leckt ein %s.';
     En: '%s is created in %s but not freed in %s: every test leaks a %s.'),
    (De: '%s wird in %s belegt, aber in %s nicht geleert: Der Leckmonitor zählt den Speicher jedem Test zu.';
     En: '%s is filled in %s but not cleared in %s: the leak monitor counts the memory against every test.'),
    (De: '%s belegt %s, die Klasse hat aber keine [%s]-Methode: Jeder Test leckt.';
     En: '%s fills %s, but the class has no [%s] method: every test leaks.'),
    (De: 'In %s freigeben'; En: 'Release in %s'),
    (De: '[%s]-Methode anlegen und freigeben'; En: 'Create a [%s] method and release'));

{$SCOPEDENUMS OFF}

const
  cStringTypes: array[0..5] of string = ('string', 'UnicodeString', 'AnsiString', 'WideString', 'RawByteString',
    'UTF8String');
  cArrayTypes: array[0..3] of string = ('TBytes', 'TStringDynArray', 'TIntegerDynArray', 'TArray');
  cFreeMethods: array[0..3] of string = ('Free', 'DisposeOf', 'Destroy', 'FreeInstance');
  cClearRoutines: array[0..2] of string = ('FreeAndNil', 'Finalize', 'SetLength');

type
  /// <summary>Ein Feld der Testklasse.</summary>
  TFixtureField = record
    Name: string;
    TypeName: string;
    Kind: TFieldKind;
  end;

  /// <summary>Ein Feld, das Setup belegt, mit der Zuweisung.</summary>
  TFilledField = record
    Field: TFixtureField;
    Assignment: TSyntaxNode;
  end;

  /// <summary>Namensmenge (klein geschrieben) ohne Groß-/Kleinschreibung.</summary>
  TNameSet = TDictionary<string, Boolean>;

  /// <summary>Eine Prüfung einer Datei.</summary>
  TTearDownCheck = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FScope: TTypedScope;
    FLineBreak: string;
    FManaged: Boolean;
    FHasFreeAndNil: Boolean;
    FRoutines: TDictionary<string, TSyntaxNode>;
    FClass: TDUnitXClass;
    FFields: TList<TFixtureField>;
    procedure CollectRoutines;
    function HasSysUtils: Boolean;
    function IsInterfaceType(ATypeNode: TSyntaxNode): Boolean;
    function KindOf(AField: TSyntaxNode; ATypeNode: TSyntaxNode): TFieldKind;
    procedure CollectFields;
    function FieldIndex(ATarget: TSyntaxNode): Integer;
    function IsOwnedCreation(AValue: TSyntaxNode): Boolean;
    function Fills(const AField: TFixtureField; AValue: TSyntaxNode): Boolean;
    function FilledIn(ARoutine: TSyntaxNode): TArray<TFilledField>;
    function WithoutHandedOver(ARoutine: TSyntaxNode; const AFilled: TArray<TFilledField>): TArray<TFilledField>;
    procedure CollectReleases(ABlock: TSyntaxNode; AFreed, ACleared: TNameSet);
    function CalledMethods(ABlock: TSyntaxNode): TArray<TSyntaxNode>;
    function Released(const AFilled: TFilledField; AFreed, ACleared: TNameSet): Boolean;
    function ReleaseText(const AField: TFixtureField; const AIndent: string): string;
    function Implementation_(const AMethod: string): TSyntaxNode;
    function MemberWith(const AAttribute: string): TDUnitXMember;
    function BodyWith(const AAttribute: string; out AMember: TDUnitXMember): TSyntaxNode;
    function InsertBeforeEnd(ARoutine: TSyntaxNode; const AFields: TArray<TFilledField>): TTextEdit;
    function NewTearDownFix(const ASetup: TDUnitXMember; ASetupBody: TSyntaxNode; const ATearDown: string;
      const AFields: TArray<TFilledField>): TRuleFix;
    procedure ReportField(const AFilled: TFilledField; const ASetup, ATearDown: string; ATearDownBody: TSyntaxNode);
    procedure CheckPair(const ASetupAttribute, ATearDownAttribute: string);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    destructor Destroy; override;
    procedure Run;
  end;

/// <summary>Name des Felds, auf das ANode zeigt (FFeld oder Self.FFeld); '' sonst.</summary>
function TargetName(ANode: TSyntaxNode): string;
var
  mNode: TSyntaxNode;
begin
  Result := '';
  mNode := Unwrapped(ANode);
  if mNode.Kind = TSyntaxKind.Identifier then
  begin
    Result := mNode.Name;
  end
  else if (mNode.Kind = TSyntaxKind.MemberAccess) and (mNode.ChildCount = 1) and
    (mNode[0].Kind = TSyntaxKind.Identifier) and SameText(mNode[0].Name, 'Self') then
  begin
    Result := mNode.Name;
  end;
end;

/// <summary>Literal '' bzw. nil oder [] (leert statt zu belegen)?</summary>
function IsEmptyValue(ANode: TSyntaxNode): Boolean;
var
  mNode: TSyntaxNode;
begin
  mNode := Unwrapped(ANode);
  Result := ((mNode.Kind = TSyntaxKind.Literal) and MatchText(mNode.Name, ['''''', 'nil'])) or
    ((mNode.Kind = TSyntaxKind.Identifier) and SameText(mNode.Name, 'nil')) or
    ((mNode.Kind = TSyntaxKind.SetConstructor) and (mNode.ChildCount = 0));
end;

/// <summary>Leerraum am Anfang der Zeile ALine von AText.</summary>
function IndentOf(const ALines: TArray<string>; ALine: Integer): string;
var
  mText: string;
  mIndex: Integer;
begin
  Result := '';
  if (ALine < 0) or (ALine > High(ALines)) then
  begin
    Exit;
  end;
  mText := ALines[ALine];
  mIndex := 1;
  while (mIndex <= Length(mText)) and CharInSet(mText[mIndex], [' ', #9]) do
  begin
    Inc(mIndex);
  end;
  Result := Copy(mText, 1, mIndex - 1);
end;

{ TTearDownCheck }

constructor TTearDownCheck.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FScope := TTypedScope.Create(AContext);
  FLineBreak := TTextLines.LineBreakOf(AContext.Text);
  FManaged := TRuleOptions.Bool(AContext.Options, 'managedFields', True);
  FRoutines := TDictionary<string, TSyntaxNode>.Create;
  FFields := TList<TFixtureField>.Create;
  FHasFreeAndNil := HasSysUtils;
  CollectRoutines;
end;

destructor TTearDownCheck.Destroy;
begin
  FFields.Free;
  FRoutines.Free;
  FScope.Free;
  inherited;
end;

procedure TTearDownCheck.CollectRoutines;
var
  mSection, mChild: TSyntaxNode;
  mIndex: Integer;
begin
  mSection := FContext.Tree.Root.FindChild(TSyntaxKind.ImplementationSection);
  if mSection = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mSection.ChildCount - 1 do
  begin
    mChild := mSection[mIndex];
    if (mChild.Kind = TSyntaxKind.RoutineDecl) and not FRoutines.ContainsKey(LowerCase(mChild.Name)) then
    begin
      FRoutines.Add(LowerCase(mChild.Name), mChild);
    end;
  end;
end;

function TTearDownCheck.HasSysUtils: Boolean;
var
  mFound: TSyntaxNode;
begin
  mFound := FContext.Tree.Root.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if (ANode.Kind = TSyntaxKind.UsedUnit) and MatchText(ANode.Name, ['System.SysUtils', 'SysUtils']) then
      begin
        Result := TSyntaxSearchStep.Found;
      end
      else if ANode.Kind in [TSyntaxKind.TypeSection, TSyntaxKind.RoutineDecl, TSyntaxKind.Block] then
      begin
        Result := TSyntaxSearchStep.Skip;
      end;
    end);
  Result := mFound <> nil;
end;

function TTearDownCheck.IsInterfaceType(ATypeNode: TSyntaxNode): Boolean;
var
  mSymbol: TResolvedSymbol;
  mName: string;
begin
  mSymbol := FScope.Resolver.ResolveType(FContext.Tree, FScope.FileName, ATypeNode.StartPos);
  if mSymbol.Kind <> TResolvedKind.None then
  begin
    Exit(mSymbol.SymbolKind = TIndexSymbolKind.InterfaceType);
  end;
  // Typ aus einer Unit ohne Index: Delphis Namensregel (IFoo) entscheidet.
  mName := ATypeNode.Name;
  mName := Copy(mName, LastDelimiter('.', mName) + 1, MaxInt);
  Result := (Length(mName) > 1) and (mName[1] = 'I') and CharInSet(mName[2], ['A'..'Z']);
end;

function TTearDownCheck.KindOf(AField: TSyntaxNode; ATypeNode: TSyntaxNode): TFieldKind;
var
  mBase: string;
begin
  Result := TFieldKind.Other;
  if AField.FindChild(TSyntaxKind.ArrayType) <> nil then
  begin
    if StartsText('array of', FScope.Text(AField.FindChild(TSyntaxKind.ArrayType))) then
    begin
      Result := TFieldKind.Array_;
    end;
    Exit;
  end;
  if ATypeNode = nil then
  begin
    Exit;
  end;
  mBase := ATypeNode.Name;
  if Pos('<', mBase) > 0 then
  begin
    mBase := Copy(mBase, 1, Pos('<', mBase) - 1);
  end;
  if MatchText(mBase, cStringTypes) then
  begin
    Result := TFieldKind.String_;
  end
  else if MatchText(mBase, cArrayTypes) then
  begin
    Result := TFieldKind.Array_;
  end
  else if not IsInterfaceType(ATypeNode) then
  begin
    Result := TFieldKind.Object_;
  end;
end;

procedure TTearDownCheck.CollectFields;
var
  mIndex: Integer;
  mChild, mType: TSyntaxNode;
  mField: TFixtureField;
  mName: string;
begin
  FFields.Clear;
  for mIndex := 0 to FClass.Body.ChildCount - 1 do
  begin
    mChild := FClass.Body[mIndex];
    if mChild.Kind <> TSyntaxKind.Field then
    begin
      Continue;
    end;
    mType := mChild.FindChild(TSyntaxKind.TypeReference);
    mField.Kind := KindOf(mChild, mType);
    mField.TypeName := FScope.Text(mChild.FindChild(TSyntaxKind.TypeReference));
    for mName in SplitString(StringReplace(mChild.Name, ' ', '', [rfReplaceAll]), ',') do
    begin
      mField.Name := mName;
      FFields.Add(mField);
    end;
  end;
end;

function TTearDownCheck.FieldIndex(ATarget: TSyntaxNode): Integer;
var
  mName: string;
begin
  mName := TargetName(ATarget);
  for Result := 0 to FFields.Count - 1 do
  begin
    if (mName <> '') and SameText(FFields[Result].Name, mName) then
    begin
      Exit;
    end;
  end;
  Result := -1;
end;

function TTearDownCheck.IsOwnedCreation(AValue: TSyntaxNode): Boolean;
var
  mArgument: TSyntaxNode;
begin
  // TButton.Create(FForm): Der Besitzer gibt frei. Literale (True, nil) sind kein Besitzer.
  Result := False;
  if (AValue.Kind <> TSyntaxKind.Call) or (AValue.ChildCount < 2) then
  begin
    Exit;
  end;
  mArgument := Unwrapped(AValue[1]);
  Result := (mArgument.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and
    not MatchText(mArgument.Name, ['nil', 'True', 'False']);
end;

function TTearDownCheck.Fills(const AField: TFixtureField; AValue: TSyntaxNode): Boolean;
var
  mValue, mCallee: TSyntaxNode;
begin
  mValue := Unwrapped(AValue);
  if AField.Kind in [TFieldKind.String_, TFieldKind.Array_] then
  begin
    Exit(FManaged and not IsEmptyValue(mValue));
  end;
  Result := False;
  if AField.Kind <> TFieldKind.Object_ then
  begin
    Exit;
  end;
  mCallee := mValue;
  if (mValue.Kind = TSyntaxKind.Call) and (mValue.ChildCount > 0) then
  begin
    mCallee := mValue[0];
  end;
  Result := (mCallee.Kind = TSyntaxKind.MemberAccess) and StartsText('Create', mCallee.Name) and
    not IsOwnedCreation(mValue);
end;

function TTearDownCheck.FilledIn(ARoutine: TSyntaxNode): TArray<TFilledField>;
var
  mFound: TArray<TFilledField>;
  mSeen: TNameSet;
begin
  mFound := nil;
  mSeen := TNameSet.Create;
  try
    ARoutine.FindChild(TSyntaxKind.Block).Walk(
      function(ANode: TSyntaxNode): Boolean
      var
        mIndex: Integer;
        mFilled: TFilledField;
      begin
        Result := ANode.Kind <> TSyntaxKind.AnonymousMethod;
        if (ANode.Kind <> TSyntaxKind.AssignStatement) or (ANode.ChildCount <> 2) then
        begin
          Exit;
        end;
        mIndex := FieldIndex(ANode[0]);
        if (mIndex >= 0) and not mSeen.ContainsKey(LowerCase(FFields[mIndex].Name)) and
          Fills(FFields[mIndex], ANode[1]) then
        begin
          mSeen.Add(LowerCase(FFields[mIndex].Name), True);
          mFilled.Field := FFields[mIndex];
          mFilled.Assignment := ANode;
          mFound := mFound + [mFilled];
        end;
      end);
  finally
    mSeen.Free;
  end;
  Result := WithoutHandedOver(ARoutine, mFound);
end;

function TTearDownCheck.WithoutHandedOver(ARoutine: TSyntaxNode;
  const AFilled: TArray<TFilledField>): TArray<TFilledField>;
var
  mHanded: TNameSet;
  mFilled: TFilledField;
begin
  // FDateien := TDateien.Create; FSystem := FDateien; Das Interface-Feld FSystem hält und gibt frei.
  mHanded := TNameSet.Create;
  try
    ARoutine.FindChild(TSyntaxKind.Block).Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        Result := ANode.Kind <> TSyntaxKind.AnonymousMethod;
        if (ANode.Kind = TSyntaxKind.AssignStatement) and (ANode.ChildCount = 2) and
          (TargetName(ANode[1]) <> '') then
        begin
          mHanded.AddOrSetValue(LowerCase(TargetName(ANode[1])), True);
        end;
      end);
    Result := nil;
    for mFilled in AFilled do
    begin
      if not ((mFilled.Field.Kind = TFieldKind.Object_) and mHanded.ContainsKey(LowerCase(mFilled.Field.Name))) then
      begin
        Result := Result + [mFilled];
      end;
    end;
  finally
    mHanded.Free;
  end;
end;

procedure MarkArguments(ANode: TSyntaxNode; ACleared: TNameSet);
var
  mIndex: Integer;
begin
  // Aufraeumen(FListe): Ein var-Parameter kann leeren; für string- und Array-Felder zählt das.
  if (ANode.Kind <> TSyntaxKind.Call) or (ANode.ChildCount < 2) then
  begin
    Exit;
  end;
  for mIndex := 1 to ANode.ChildCount - 1 do
  begin
    if TargetName(ANode[mIndex]) <> '' then
    begin
      ACleared.AddOrSetValue(LowerCase(TargetName(ANode[mIndex])), True);
    end;
  end;
end;

procedure TTearDownCheck.CollectReleases(ABlock: TSyntaxNode; AFreed, ACleared: TNameSet);
begin
  ABlock.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      mName: string;
    begin
      Result := True;
      mName := '';
      MarkArguments(ANode, ACleared);
      // FreeAndNil(F), Finalize(F), SetLength(F, 0)
      if (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount >= 2) and (ANode[0].Kind = TSyntaxKind.Identifier) and
        MatchText(ANode[0].Name, cClearRoutines) then
      begin
        mName := TargetName(ANode[1]);
      end
      // F.Free, F.DisposeOf
      else if (ANode.Kind = TSyntaxKind.MemberAccess) and MatchText(ANode.Name, cFreeMethods) and
        (ANode.ChildCount = 1) then
      begin
        mName := TargetName(ANode[0]);
      end
      // F := nil, F := ''
      else if (ANode.Kind = TSyntaxKind.AssignStatement) and (ANode.ChildCount = 2) then
      begin
        ACleared.AddOrSetValue(LowerCase(TargetName(ANode[0])), True);
        if IsEmptyValue(ANode[1]) then
        begin
          mName := TargetName(ANode[0]);
        end;
      end;
      if mName <> '' then
      begin
        AFreed.AddOrSetValue(LowerCase(mName), True);
        ACleared.AddOrSetValue(LowerCase(mName), True);
      end;
    end);
end;

function TTearDownCheck.CalledMethods(ABlock: TSyntaxNode): TArray<TSyntaxNode>;
var
  mFound: TArray<TSyntaxNode>;
begin
  mFound := nil;
  ABlock.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      mName: string;
      mRoutine: TSyntaxNode;
    begin
      Result := True;
      mName := '';
      if ANode.Kind = TSyntaxKind.CallStatement then
      begin
        if (ANode.ChildCount > 0) and (ANode[0].Kind = TSyntaxKind.Call) then
        begin
          mName := TargetName(ANode[0][0]);
        end
        else if ANode.ChildCount > 0 then
        begin
          mName := TargetName(ANode[0]);
        end;
      end;
      mRoutine := nil;
      if (mName <> '') and FRoutines.TryGetValue(LowerCase(FClass.Name + '.' + mName), mRoutine) and
        (mRoutine.FindChild(TSyntaxKind.Block) <> nil) then
      begin
        mFound := mFound + [mRoutine.FindChild(TSyntaxKind.Block)];
      end;
    end);
  Result := mFound;
end;

function TTearDownCheck.Released(const AFilled: TFilledField; AFreed, ACleared: TNameSet): Boolean;
begin
  if AFilled.Field.Kind = TFieldKind.Object_ then
  begin
    Result := AFreed.ContainsKey(LowerCase(AFilled.Field.Name));
  end
  else
  begin
    Result := ACleared.ContainsKey(LowerCase(AFilled.Field.Name));
  end;
end;

function TTearDownCheck.ReleaseText(const AField: TFixtureField; const AIndent: string): string;
begin
  case AField.Kind of
    TFieldKind.String_:
      Result := AIndent + AField.Name + ' := '''';' + FLineBreak;
    TFieldKind.Array_:
      Result := AIndent + AField.Name + ' := nil;' + FLineBreak;
  else
    if FHasFreeAndNil then
    begin
      Result := AIndent + 'FreeAndNil(' + AField.Name + ');' + FLineBreak;
    end
    else
    begin
      Result := AIndent + AField.Name + '.Free;' + FLineBreak + AIndent + AField.Name + ' := nil;' + FLineBreak;
    end;
  end;
end;

function TTearDownCheck.Implementation_(const AMethod: string): TSyntaxNode;
begin
  if not FRoutines.TryGetValue(LowerCase(FClass.Name + '.' + AMethod), Result) or
    (Result.FindChild(TSyntaxKind.Block) = nil) then
  begin
    Result := nil;
  end;
end;

function TTearDownCheck.MemberWith(const AAttribute: string): TDUnitXMember;
var
  mMember: TDUnitXMember;
begin
  Result := Default(TDUnitXMember);
  for mMember in FClass.Members do
  begin
    if (mMember.Node.Kind = TSyntaxKind.RoutineHeader) and TDUnitXClasses.HasItem(mMember.Attributes, AAttribute) then
    begin
      Exit(mMember);
    end;
  end;
end;

function TTearDownCheck.BodyWith(const AAttribute: string; out AMember: TDUnitXMember): TSyntaxNode;
begin
  AMember := MemberWith(AAttribute);
  Result := nil;
  if AMember.Node <> nil then
  begin
    Result := Implementation_(AMember.Node.Name);
  end;
end;

function TTearDownCheck.InsertBeforeEnd(ARoutine: TSyntaxNode; const AFields: TArray<TFilledField>): TTextEdit;
var
  mBlock: TSyntaxNode;
  mLines: TArray<string>;
  mEnd: TTextPosition;
  mLineBreak, mIndent, mText: string;
  mFilled: TFilledField;
begin
  // Vor dem end des Rumpfs; steht es allein auf seiner Zeile, als eigene Zeile davor.
  mBlock := ARoutine.FindChild(TSyntaxKind.Block);
  mLines := TTextLines.SplitLines(FContext.Text, mLineBreak);
  mEnd := TTextPosition.Create(mBlock.EndPos.Line, mBlock.EndPos.Character - 3);
  mIndent := IndentOf(mLines, mEnd.Line);
  mText := '';
  if Length(mIndent) = mEnd.Character then
  begin
    for mFilled in AFields do
    begin
      mText := mText + ReleaseText(mFilled.Field, mIndent + '  ');
    end;
    mEnd := TTextPosition.Create(mEnd.Line, 0);
  end
  else
  begin
    for mFilled in AFields do
    begin
      mText := mText + Trim(ReleaseText(mFilled.Field, '')) + ' ';
    end;
  end;
  Result := TTextEdit.Create(TTextRange.Create(mEnd, mEnd), mText);
end;

function TTearDownCheck.NewTearDownFix(const ASetup: TDUnitXMember; ASetupBody: TSyntaxNode;
  const ATearDown: string; const AFields: TArray<TFilledField>): TRuleFix;
var
  mLines: TArray<string>;
  mLineBreak, mIndent, mBody: string;
  mFilled: TFilledField;
  mDecl, mImpl: TTextPosition;
begin
  mLines := TTextLines.SplitLines(FContext.Text, mLineBreak);
  mIndent := IndentOf(mLines, ASetup.Node.StartPos.Line);
  mBody := '';
  for mFilled in AFields do
  begin
    mBody := mBody + ReleaseText(mFilled.Field, '  ');
  end;
  mDecl := TTextPosition.Create(ASetup.Node.EndPos.Line + 1, 0);
  mImpl := TTextPosition.Create(ASetupBody.EndPos.Line + 1, 0);
  Result := TRuleFix.Create(cTexts[TTearDownText.CreateTearDown].Fmt([ATearDown]), [
    TTextEdit.Create(TTextRange.Create(mDecl, mDecl), mIndent + '[' + ATearDown + ']' + FLineBreak + mIndent +
      'procedure ' + ATearDown + ';' + FLineBreak),
    TTextEdit.Create(TTextRange.Create(mImpl, mImpl), FLineBreak + 'procedure ' + FClass.Name + '.' + ATearDown +
      ';' + FLineBreak + 'begin' + FLineBreak + mBody + 'end;' + FLineBreak)], True);
end;

procedure TTearDownCheck.ReportField(const AFilled: TFilledField; const ASetup, ATearDown: string;
  ATearDownBody: TSyntaxNode);
var
  mFix: TRuleFix;
  mMessage: string;
begin
  mFix := TRuleFix.Create(cTexts[TTearDownText.ReleaseIn].Fmt([ATearDown]), [InsertBeforeEnd(ATearDownBody,
    [AFilled])], True);
  if AFilled.Field.Kind = TFieldKind.Object_ then
  begin
    mMessage := cTexts[TTearDownText.NotFreed].Fmt([AFilled.Field.Name, ASetup, ATearDown, AFilled.Field.TypeName]);
  end
  else
  begin
    mMessage := cTexts[TTearDownText.NotCleared].Fmt([AFilled.Field.Name, ASetup, ATearDown]);
  end;
  FReport.Add(TTextRange.Create(AFilled.Assignment.StartPos, AFilled.Assignment.EndPos), mMessage,
    TRuleConfidence.Medium, [mFix]);
end;

procedure TTearDownCheck.CheckPair(const ASetupAttribute, ATearDownAttribute: string);
var
  mSetup, mTearDown: TDUnitXMember;
  mSetupBody, mTearDownBody, mBlock: TSyntaxNode;
  mFilled: TArray<TFilledField>;
  mFreed, mCleared: TNameSet;
  mOne: TFilledField;
  mNames: string;
begin
  mSetupBody := BodyWith(ASetupAttribute, mSetup);
  if mSetupBody = nil then
  begin
    Exit;
  end;
  mFilled := FilledIn(mSetupBody);
  if mFilled = nil then
  begin
    Exit;
  end;
  mTearDownBody := BodyWith(ATearDownAttribute, mTearDown);
  if mTearDownBody = nil then
  begin
    mNames := '';
    for mOne in mFilled do
    begin
      mNames := mNames + IfThen(mNames <> '', ', ') + mOne.Field.Name;
    end;
    FReport.Add(TTextRange.Create(mSetup.Node.StartPos, mSetup.Node.EndPos), cTexts[TTearDownText.NoTearDown].Fmt(
      [mSetup.Node.Name, mNames, ATearDownAttribute]), TRuleConfidence.Medium,
      [NewTearDownFix(mSetup, mSetupBody, ATearDownAttribute, mFilled)]);
    Exit;
  end;
  mFreed := TNameSet.Create;
  mCleared := TNameSet.Create;
  try
    CollectReleases(mTearDownBody.FindChild(TSyntaxKind.Block), mFreed, mCleared);
    for mBlock in CalledMethods(mTearDownBody.FindChild(TSyntaxKind.Block)) do
    begin
      CollectReleases(mBlock, mFreed, mCleared);
    end;
    for mOne in mFilled do
    begin
      if not Released(mOne, mFreed, mCleared) then
      begin
        ReportField(mOne, mSetup.Node.Name, mTearDown.Node.Name, mTearDownBody);
      end;
    end;
  finally
    mCleared.Free;
    mFreed.Free;
  end;
end;

procedure TTearDownCheck.Run;
var
  mClass: TDUnitXClass;
begin
  for mClass in TDUnitXClasses.Collect(FContext.Tree.Root) do
  begin
    FClass := mClass;
    CollectFields;
    if FFields.Count > 0 then
    begin
      CheckPair('Setup', 'TearDown');
      CheckPair('SetupFixture', 'TearDownFixture');
    end;
  end;
end;

{ TDUnitXSetupNotTornDownRule }

function TDUnitXSetupNotTornDownRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cDUnitXSetupNotTornDownRuleId, TRuleSeverity.Warning,
    cTexts[TTearDownText.Title].Text);
end;

procedure TDUnitXSetupNotTornDownRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mCheck: TTearDownCheck;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not ContainsText(AContext.Text, 'Setup') or
    not TUsesClauses.IsTestUnit(AContext.Tree.Tokens) then
  begin
    Exit;
  end;
  mCheck := TTearDownCheck.Create(AContext, AReport);
  try
    mCheck.Run;
  finally
    mCheck.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Testing.TearDown', cTexts);

end.
