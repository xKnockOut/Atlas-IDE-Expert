unit Atlas.Common.Rules.Builtin.InvalidDeclarations;

// Deklarationen, die der Compiler ablehnt und die keine andere Regel abdeckt
// (#1380, Gruppe Compiler vorab, aus dem dcc-Abgleich Tests/Compilermeldungen):
//   declaration-invalid  packed vor einem Typnamen statt vor array, record,
//                        object, class, set oder file (wie E2006), eine
//                        Funktion mit dem Ergebnistyp file (wie E2024), ein
//                        virtueller Konstruktor in einem object-Typ (wie
//                        E2062), eine Property ohne read und write in einem
//                        Interface oder im Abschnitt automated (wie E2128)
//                        und zwei Konstruktoren einer Klasse mit denselben
//                        Parametertypen, wenn das Projekt C++-Dateien erzeugt
//                        (wie W1029).
//
// Die Regel liest den Syntaxbaum aus den aktiven Zweigen und die Token davor.
// W1029 meldet dcc nur mit C++-Ausgabe (-J…, DCC_CBuilderOutput in der .dproj,
// Cm.W1029 mit -JPHNE); ohne Projekt oder ohne diese Einstellung bleibt die
// Prüfung still. dispinterface-Properties brauchen kein read und write. Hinter
// packed bleiben string und file still (packed string[n], packed file of).

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  cDeclarationInvalidRuleId = 'declaration-invalid';

type
  TDeclarationInvalidRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Erzeugt das Projekt mit dem Text ADproj C++-Dateien (DCC_CBuilderOutput außer None, -J… in
    /// DCC_AdditionalSwitches)? Dann meldet dcc W1029.</summary>
    class function CppOutput(const ADproj: string): Boolean; static;
  end;

procedure RegisterInvalidDeclarationRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TInvalidDeclarationsText = (Title, PackedType, FileResult, VirtualObjectConstructor, PropertyAccess,
    AutomatedAccess, SameConstructors);

const
  cTexts: array[TInvalidDeclarationsText] of TAtlasText = (
    (De: 'Deklaration, die der Compiler ablehnt'; En: 'Declaration the compiler rejects'),
    (De: 'packed gilt nur für array, record, object, class, set und file, nicht für %s (wie E2006).';
     En: 'packed applies only to array, record, object, class, set and file, not to %s (like E2006).'),
    (De: '%s kann keine Datei liefern; der Ergebnistyp file ist nicht erlaubt (wie E2024).';
     En: '%s cannot return a file; the result type file is not allowed (like E2024).'),
    (De: 'Der Konstruktor %s eines object-Typs darf nicht virtual sein (wie E2062).';
     En: 'The constructor %s of an object type must not be virtual (like E2062).'),
    (De: 'Die Property %s braucht read oder write; ein Interface kennt keine Property ohne Zugriff (wie E2128).';
     En: 'The property %s needs read or write; an interface knows no property without access (like E2128).'),
    (De: 'Die Property %s im Abschnitt automated braucht read oder write (wie E2128).';
     En: 'The property %s in the automated section needs read or write (like E2128).'),
    (De: 'Die Konstruktoren %s und %s haben dieselben Parametertypen; aus C++ ist %s nicht erreichbar (wie W1029).';
     En: 'The constructors %s and %s have the same parameter types; %s is not reachable from C++ (like W1029).'));

{$SCOPEDENUMS OFF}

/// <summary>Bezeichner oder Schlüsselwort mit Text AWord (ohne Groß-/Kleinschreibung)?</summary>
function IsWord(const AToken: TPascalToken; const AWord: string): Boolean;
begin
  Result := (AToken.Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) and SameText(AToken.Text, AWord);
end;

function IsTrivia(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
end;

/// <summary>Werte des Elements ATag in der .dproj ADproj, in der Reihenfolge des Textes.</summary>
function ElementValues(const ADproj, ATag: string): TArray<string>;
var
  mOpen, mClose: string;
  mStart, mStop: Integer;
begin
  Result := nil;
  mOpen := '<' + ATag + '>';
  mClose := '</' + ATag + '>';
  mStart := Pos(mOpen, ADproj);
  while mStart > 0 do
  begin
    mStart := mStart + Length(mOpen);
    mStop := PosEx(mClose, ADproj, mStart);
    if mStop = 0 then
    begin
      Break;
    end;
    Result := Result + [Trim(Copy(ADproj, mStart, mStop - mStart))];
    mStart := PosEx(mOpen, ADproj, mStop);
  end;
end;

{ TDeclarationInvalidRule }

function TDeclarationInvalidRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cDeclarationInvalidRuleId, TRuleSeverity.Error,
    cTexts[TInvalidDeclarationsText.Title].Text);
end;

class function TDeclarationInvalidRule.CppOutput(const ADproj: string): Boolean;
var
  mValue, mSwitch: string;
begin
  for mValue in ElementValues(ADproj, 'DCC_CBuilderOutput') do
  begin
    if (mValue <> '') and not SameText(mValue, 'None') then
    begin
      Exit(True);
    end;
  end;
  for mValue in ElementValues(ADproj, 'DCC_AdditionalSwitches') do
  begin
    for mSwitch in mValue.Split([' ', #9]) do
    begin
      if StartsText('-J', mSwitch) then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

procedure TDeclarationInvalidRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TArray<TPascalToken>;
  mCppKnown, mCpp: Boolean;

  function TokenRange(AIndex: Integer): TTextRange;
  begin
    Result := TTextRange.Create(mTokens[AIndex].StartPos, mTokens[AIndex].EndPos);
  end;

  function NodeRange(ANode: TSyntaxNode): TTextRange;
  begin
    Result := TTextRange.Create(ANode.StartPos, ANode.EndPos);
  end;

  /// <summary>Erstes Code-Token von ANode; Length(Tokens) ohne.</summary>
  function FirstCode(ANode: TSyntaxNode): Integer;
  begin
    Result := AContext.Tree.FirstTokenFrom(ANode.StartOffset);
    while (Result < Length(mTokens)) and IsTrivia(mTokens[Result]) do
    begin
      Inc(Result);
    end;
  end;

  /// <summary>Code-Token vor AIndex; -1 ohne.</summary>
  function PreviousCode(AIndex: Integer): Integer;
  begin
    Result := AIndex - 1;
    while (Result >= 0) and IsTrivia(mTokens[Result]) do
    begin
      Dec(Result);
    end;
  end;

  function HasDirective(AHeader: TSyntaxNode; const AName: string; out ADirective: TSyntaxNode): Boolean;
  var
    mIndex: Integer;
  begin
    for mIndex := 0 to AHeader.ChildCount - 1 do
    begin
      if (AHeader[mIndex].Kind = TSyntaxKind.Directive) and SameText(AHeader[mIndex].Name, AName) then
      begin
        ADirective := AHeader[mIndex];
        Exit(True);
      end;
    end;
    ADirective := nil;
    Result := False;
  end;

  /// <summary>Konstruktor (nicht class constructor)?</summary>
  function IsConstructor(AHeader: TSyntaxNode): Boolean;
  var
    mFirst: Integer;
  begin
    mFirst := FirstCode(AHeader);
    Result := (mFirst < Length(mTokens)) and IsWord(mTokens[mFirst], 'constructor');
  end;

  /// <summary>E2006: packed vor einem Typnamen (packed Integer).</summary>
  procedure CheckPacked(AReference: TSyntaxNode);
  var
    mBefore: Integer;
  begin
    if MatchText(AReference.Name, ['string', 'file']) then
    begin
      Exit;
    end;
    mBefore := PreviousCode(FirstCode(AReference));
    if (mBefore >= 0) and IsWord(mTokens[mBefore], 'packed') then
    begin
      AReport.Add(TokenRange(mBefore), cTexts[TInvalidDeclarationsText.PackedType].Fmt([AReference.Name]),
        TRuleConfidence.High);
    end;
  end;

  /// <summary>E2024: function … : file.</summary>
  procedure CheckResult(AHeader: TSyntaxNode);
  var
    mIndex: Integer;
  begin
    for mIndex := 0 to AHeader.ChildCount - 1 do
    begin
      if (AHeader[mIndex].Kind = TSyntaxKind.TypeReference) and SameText(AHeader[mIndex].Name, 'file') then
      begin
        AReport.Add(NodeRange(AHeader[mIndex]), cTexts[TInvalidDeclarationsText.FileResult].Fmt([AHeader.Name]),
          TRuleConfidence.High);
      end;
    end;
  end;

  /// <summary>E2062: virtueller Konstruktor in einem object-Typ.</summary>
  procedure CheckObject(AObject: TSyntaxNode);
  var
    mIndex: Integer;
    mVirtual: TSyntaxNode;
  begin
    for mIndex := 0 to AObject.ChildCount - 1 do
    begin
      if (AObject[mIndex].Kind = TSyntaxKind.RoutineHeader) and IsConstructor(AObject[mIndex]) and
        HasDirective(AObject[mIndex], 'virtual', mVirtual) then
      begin
        AReport.Add(NodeRange(mVirtual),
          cTexts[TInvalidDeclarationsText.VirtualObjectConstructor].Fmt([AObject[mIndex].Name]), TRuleConfidence.High);
      end;
    end;
  end;

  /// <summary>Steht read, write oder index in der Property AProperty?</summary>
  function HasAccessor(AProperty: TSyntaxNode): Boolean;
  var
    mIndex: Integer;
  begin
    mIndex := FirstCode(AProperty);
    while (mIndex < Length(mTokens)) and (mTokens[mIndex].Offset < AProperty.EndOffset) do
    begin
      if IsWord(mTokens[mIndex], 'read') or IsWord(mTokens[mIndex], 'write') or IsWord(mTokens[mIndex], 'index') then
      begin
        Exit(True);
      end;
      Inc(mIndex);
    end;
    Result := False;
  end;

  /// <summary>Token des Namens von ANode (Property, Methode); erstes Code-Token ohne.</summary>
  function NameToken(ANode: TSyntaxNode): Integer;
  begin
    Result := FirstCode(ANode);
    while (Result < Length(mTokens)) and (mTokens[Result].Offset < ANode.EndOffset) and
      not ((mTokens[Result].Kind = TPascalTokenKind.Identifier) and SameText(mTokens[Result].Text, ANode.Name)) do
    begin
      Inc(Result);
    end;
    if (Result >= Length(mTokens)) or (mTokens[Result].Offset >= ANode.EndOffset) then
    begin
      Result := FirstCode(ANode);
    end;
  end;

  /// <summary>E2128: Property ohne read und write in einem Interface (nicht dispinterface) bzw. im Abschnitt
  /// automated einer Klasse.</summary>
  procedure CheckProperties(AType: TSyntaxNode; AInterface: Boolean);
  var
    mIndex, mFirst: Integer;
    mAutomated: Boolean;
    mChild: TSyntaxNode;
  begin
    if AInterface then
    begin
      mFirst := FirstCode(AType);
      if (mFirst < Length(mTokens)) and IsWord(mTokens[mFirst], 'dispinterface') then
      begin
        Exit;
      end;
    end;
    mAutomated := False;
    for mIndex := 0 to AType.ChildCount - 1 do
    begin
      mChild := AType[mIndex];
      if mChild.Kind = TSyntaxKind.Visibility then
      begin
        mAutomated := SameText(mChild.Name, 'automated');
      end
      else if (mChild.Kind = TSyntaxKind.PropertyDecl) and (AInterface or mAutomated) and
        not HasAccessor(mChild) then
      begin
        if AInterface then
        begin
          AReport.Add(TokenRange(NameToken(mChild)), cTexts[TInvalidDeclarationsText.PropertyAccess].Fmt([mChild.Name]),
            TRuleConfidence.High);
        end
        else
        begin
          AReport.Add(TokenRange(NameToken(mChild)),
            cTexts[TInvalidDeclarationsText.AutomatedAccess].Fmt([mChild.Name]), TRuleConfidence.High);
        end;
      end;
    end;
  end;

  /// <summary>Text der Token von ANode in Kleinbuchstaben, ohne Leerraum und Kommentare.</summary>
  function CodeText(ANode: TSyntaxNode): string;
  var
    mIndex: Integer;
  begin
    Result := '';
    mIndex := FirstCode(ANode);
    while (mIndex < Length(mTokens)) and (mTokens[mIndex].Offset < ANode.EndOffset) do
    begin
      if not IsTrivia(mTokens[mIndex]) then
      begin
        Result := Result + LowerCase(mTokens[mIndex].Text);
      end;
      Inc(mIndex);
    end;
  end;

  function IsModifier(const AToken: TPascalToken): Boolean;
  begin
    Result := (AToken.Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) and
      MatchText(AToken.Text, ['const', 'var', 'out', 'constref']);
  end;

  /// <summary>Parametertypen von AHeader wie "const:integer;var:string;var:string"; je Name ein Eintrag.</summary>
  function ParameterKey(AHeader: TSyntaxNode): string;
  var
    mParams, mParam: TSyntaxNode;
    mIndex, mName, mBefore: Integer;
    mModifier, mType: string;
  begin
    Result := '';
    mParams := AHeader.FindChild(TSyntaxKind.Parameters);
    if mParams = nil then
    begin
      Exit;
    end;
    for mIndex := 0 to mParams.ChildCount - 1 do
    begin
      mParam := mParams[mIndex];
      if mParam.Kind <> TSyntaxKind.Parameter then
      begin
        Continue;
      end;
      // Der Modifizierer steht vor dem Namen; je nach Knoten gehört er schon zum Parameter.
      mModifier := '';
      mBefore := FirstCode(mParam);
      if (mBefore < Length(mTokens)) and not IsModifier(mTokens[mBefore]) then
      begin
        mBefore := PreviousCode(mBefore);
      end;
      if (mBefore >= 0) and (mBefore < Length(mTokens)) and IsModifier(mTokens[mBefore]) then
      begin
        mModifier := LowerCase(mTokens[mBefore].Text);
      end;
      mType := '';
      if mParam.ChildCount > 0 then
      begin
        mType := CodeText(mParam[0]);
      end;
      for mName := 0 to High(mParam.Name.Split([','])) do
      begin
        Result := Result + mModifier + ':' + mType + ';';
      end;
    end;
  end;

  function CppProject: Boolean;
  var
    mFileName, mText: string;
  begin
    if not mCppKnown then
    begin
      mCppKnown := True;
      mCpp := (AContext.Units <> nil) and AContext.Units.ReadProject(mFileName, mText) and CppOutput(mText);
    end;
    Result := mCpp;
  end;

  /// <summary>W1029 am Konstruktor AHeader, wenn ein früherer anderen Namens (AHeaders, Schlüssel AKeys) dieselben
  /// Parametertypen AKey hat.</summary>
  procedure CheckConstructor(AHeader: TSyntaxNode; const AKey: string; const AHeaders: TArray<TSyntaxNode>;
    const AKeys: TArray<string>);
  var
    mEarlier: Integer;
  begin
    for mEarlier := 0 to High(AHeaders) do
    begin
      if (AKeys[mEarlier] = AKey) and not SameText(AHeaders[mEarlier].Name, AHeader.Name) then
      begin
        if CppProject then
        begin
          AReport.Add(TokenRange(NameToken(AHeader)),
            cTexts[TInvalidDeclarationsText.SameConstructors].Fmt([AHeaders[mEarlier].Name, AHeader.Name,
            AHeader.Name]), TRuleConfidence.High);
        end;
        Exit;
      end;
    end;
  end;

  /// <summary>W1029: zwei Konstruktoren der Klasse mit denselben Parametertypen.</summary>
  procedure CheckConstructors(AClass: TSyntaxNode);
  var
    mIndex: Integer;
    mHeaders: TArray<TSyntaxNode>;
    mKeys: TArray<string>;
    mKey: string;
  begin
    mHeaders := nil;
    mKeys := nil;
    for mIndex := 0 to AClass.ChildCount - 1 do
    begin
      if (AClass[mIndex].Kind = TSyntaxKind.RoutineHeader) and IsConstructor(AClass[mIndex]) then
      begin
        mKey := ParameterKey(AClass[mIndex]);
        CheckConstructor(AClass[mIndex], mKey, mHeaders, mKeys);
        mHeaders := mHeaders + [AClass[mIndex]];
        mKeys := mKeys + [mKey];
      end;
    end;
  end;

  // Iterativ (Bericht M1): nur Deklarationen, keine Anweisungen.
  procedure Visit(ARoot: TSyntaxNode);
  var
    mPending: TStack<TSyntaxNode>;
    mNode: TSyntaxNode;
    mIndex: Integer;
  begin
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ARoot);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        case mNode.Kind of
          TSyntaxKind.TypeReference:
            CheckPacked(mNode);
          TSyntaxKind.RoutineHeader:
            CheckResult(mNode);
          TSyntaxKind.ObjectType:
            CheckObject(mNode);
          TSyntaxKind.InterfaceType:
            CheckProperties(mNode, True);
          TSyntaxKind.ClassType:
            begin
              CheckProperties(mNode, False);
              CheckConstructors(mNode);
            end;
        else
          // Übrige Arten: nichts zu tun.
        end;
        if mNode.Kind in [TSyntaxKind.Block, TSyntaxKind.AsmBlock] then
        begin
          Continue;
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

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  mCppKnown := False;
  mCpp := False;
  Visit(AContext.Tree.Root);
end;

procedure RegisterInvalidDeclarationRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TDeclarationInvalidRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.InvalidDeclarations', cTexts);

end.
