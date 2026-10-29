unit Atlas.Common.Rules.Builtin.StringConversions;

// Umwandlungen zwischen String- und Zeichentypen (#1377, Gruppe „Compiler
// vorab“, Stufe T), wie die Compilerwarnungen W1050–W1068:
//   W1057  implizit von AnsiString, RawByteString oder UTF8String in string,
//          UnicodeString oder WideString bzw. von diesen in UTF8String
//   W1058  implizit von string, UnicodeString oder WideString in AnsiString
//          bzw. RawByteString (Zeichen können verloren gehen)
//   W1059  ausdrücklich verlustfrei (string(A) mit A: AnsiString)
//   W1060  ausdrücklich mit möglichem Verlust (AnsiString(S) mit S: string)
//   W1062  Stringkonstante mit Zeichen, die die ANSI-Codepage nicht kennt, an
//          AnsiString (dcc meldet dazu W1058; beides steht in einer Meldung)
//   W1050  WideChar in einem Mengenausdruck aus Zeichenliteralen
//          (C in ['0'..'9']); Korrektur CharInSet samt System.SysUtils
//   W1068  Zeichen eines string direkt geändert (S[1] := 'x')
//
// Implizit heißt: Zuweisung, Inline-Variable mit Typ und Argument an einen
// Wert- oder const-Parameter einer Routine ohne Überladungen. Gemeldet wird
// nur, wenn beide Typen sicher bekannt sind (Variablen, Felder, Properties,
// Funktionsergebnisse und typisierte Konstanten mit eingebautem Stringtyp aus
// System, deren Deklaration immer mit der Stelle übersetzt wird). Ausdrücke
// mit + und Umwandlungen als Quelle meldet die Regel nicht; zwischen zwei
// Ansi-Typen (AnsiString, RawByteString, UTF8String) wandelt dcc je nach
// Codepage um, auch das bleibt still. Einfache Aliase (TText = AnsiString)
// sind derselbe Typ und zählen mit; eigene Typen (type AnsiString(28591)) und
// ShortString nicht.
//
// Wie dcc: W1059, W1060 und W1068 meldet der Compiler nur nach
// {$WARN EXPLICIT_STRING_CAST ON}, {$WARN EXPLICIT_STRING_CAST_LOSS ON} bzw.
// {$WARN IMMUTABLE_STRINGS ON}; die übrigen sind an. {$WARN … OFF} und
// {$WARNINGS OFF} schalten ab, {$WARN … ERROR} meldet als Fehler
// (Rules.WarnSwitches), ebenso DCC_<Bezeichner> der .dproj.
// Mit {$H-} bzw. {$LONGSTRINGS OFF} in der Datei (string = ShortString) und
// vor Delphi 2009 (BDS 6.0, Char = AnsiChar) schweigt sie ganz.
//
// W1062 hängt von der ANSI-Codepage des Rechners ab, auf dem übersetzt wird
// (Option ansiCodePage, Vorgabe 1252; 0 schaltet die Prüfung ab). Gemeldet
// werden nur Zeichen, die Windows für 1252 auch nicht ersatzweise abbildet
// (best fit): Hebräisch bis Thai, Hangul, Kana und CJK, Symbole und Dingbats
// U+2600–U+27BF und Zeichen außerhalb der BMP (Emoji). Andere Codepages kennt
// die Regel nicht und schweigt dort.

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  StringConversionRuleId = 'string-conversion';

type
{$SCOPEDENUMS ON}
  /// <summary>Art eines eingebauten Stringtyps: UTF-16 (string, UnicodeString, WideString), Ansi (AnsiString,
  /// RawByteString), UTF-8 (UTF8String), sonst None.</summary>
  TStringTypeKind = (None, Unicode, Ansi, Utf8);
{$SCOPEDENUMS OFF}

  TStringConversionRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Art des eingebauten Stringtyps ATypeName (auch mit "System."); None für andere.</summary>
    class function KindOf(const ATypeName: string): TStringTypeKind; static;
    /// <summary>Code der Umwandlung von AFrom nach ATo: implizit W1057 bzw. W1058, ausdrücklich (AExplicit)
    /// W1059 bzw. W1060; '' ohne Meldung (gleiche Art, zwischen Ansi-Typen, unbekannt).</summary>
    class function ConversionCode(AFrom, ATo: TStringTypeKind; AExplicit: Boolean): string; static;
    /// <summary>Geht AChar bei der Umwandlung in die Codepage 1252 sicher verloren (auch kein Ersatzzeichen)?
    /// </summary>
    class function LostIn1252(AChar: Char): Boolean; static;
  end;

procedure RegisterStringConversionRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.WarningCodes,
  Atlas.Common.Pascal.FormatStrings,
  Atlas.Common.Pascal.LanguageFeatures,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.TypedScope,
  Atlas.Common.Rules.WarnSwitches,
  Atlas.Common.Rules.Builtin.TypeChecks,
  Atlas.Text.Lines;

const
  cMaxValueText = 30;
  cDefaultCodePage = 1252;
  // Erste Version mit Char = WideChar und string = UnicodeString (Delphi 2009).
  cUnicodeVersion = '6.0';

{ TStringConversionRule }

function TStringConversionRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(StringConversionRuleId, TRuleSeverity.Warning,
    'Umwandlung zwischen Unicode- und ANSI-Strings');
end;

class function TStringConversionRule.KindOf(const ATypeName: string): TStringTypeKind;
var
  mName: string;
begin
  mName := Trim(ATypeName);
  if StartsText('System.', mName) then
    mName := Copy(mName, Length('System.') + 1, MaxInt);
  if MatchText(mName, ['string', 'UnicodeString', 'WideString']) then
    Result := TStringTypeKind.Unicode
  else if MatchText(mName, ['AnsiString', 'RawByteString']) then
    Result := TStringTypeKind.Ansi
  else if SameText(mName, 'UTF8String') then
    Result := TStringTypeKind.Utf8
  else
    Result := TStringTypeKind.None;
end;

class function TStringConversionRule.ConversionCode(AFrom, ATo: TStringTypeKind; AExplicit: Boolean): string;
begin
  Result := '';
  if (AFrom = TStringTypeKind.None) or (ATo = TStringTypeKind.None) or (AFrom = ATo) or
    ((AFrom <> TStringTypeKind.Unicode) and (ATo <> TStringTypeKind.Unicode)) then
    Exit;
  // Nur in AnsiString bzw. RawByteString gehen Zeichen verloren; UTF-8 fasst alle.
  if ATo = TStringTypeKind.Ansi then
  begin
    if AExplicit then
      Result := 'W1060'
    else
      Result := 'W1058';
  end
  else if AExplicit then
    Result := 'W1059'
  else
    Result := 'W1057';
end;

class function TStringConversionRule.LostIn1252(AChar: Char): Boolean;
var
  mCode: Integer;
begin
  mCode := Ord(AChar);
  // Hebräisch, Arabisch, Syrisch … bis Thai; Hangul Jamo; Symbole und Dingbats; Kana und CJK; Hangul-Silben;
  // Ersatzzeichen (Emoji und alles außerhalb der BMP).
  Result := ((mCode >= $0590) and (mCode <= $0E7F)) or ((mCode >= $1100) and (mCode <= $11FF)) or
    ((mCode >= $2600) and (mCode <= $27BF)) or ((mCode >= $3040) and (mCode <= $9FFF)) or
    ((mCode >= $AC00) and (mCode <= $D7A3)) or ((mCode >= $D800) and (mCode <= $DFFF));
end;

/// <summary>Vorgabe von dcc: W1059, W1060 und W1068 sind beim Compiler aus, die übrigen an.</summary>
function DefaultOn(const ACode: string): Boolean;
begin
  Result := not MatchText(ACode, ['W1059', 'W1060', 'W1068']);
end;

procedure TStringConversionRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mScope: TTypedScope;
  mSwitches: TRuleWarnSwitches;
  mCodePage: Integer;

  function NodeText(ANode: TSyntaxNode): string;
  begin
    Result := mScope.Text(ANode);
  end;

  function ValueText(ANode: TSyntaxNode): string;
  begin
    Result := NodeText(ANode);
    if Length(Result) > cMaxValueText then
      Result := 'Der Wert';
  end;

  function StateOf(const ACode: string; ANode: TSyntaxNode): TRuleWarnState;
  begin
    Result := mSwitches.StateAtOffset(TWarningCodes.Identifier(ACode, AContext.DelphiVersion), DefaultOn(ACode),
      ANode.StartOffset);
  end;

  /// <summary>Meldet AMessage an ANode, wenn der Compiler ACode dort meldet; als Fehler nach {$WARN … ERROR}.
  /// </summary>
  procedure Report(const ACode: string; ANode: TSyntaxNode; const AMessage: string; AConfidence: TRuleConfidence;
    const AFixes: TArray<TRuleFix>);
  var
    mState: TRuleWarnState;
  begin
    mState := StateOf(ACode, ANode);
    if mState = TRuleWarnState.AsError then
      AReport.AddWithSeverity(TTextRange.Create(ANode.StartPos, ANode.EndPos), AMessage, TRuleSeverity.Error, AFixes)
    else if mState = TRuleWarnState.Enabled then
      AReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos), AMessage, AConfidence, AFixes);
  end;

  /// <summary>Ist ATypeInfo ein eingebauter Typ aus System?</summary>
  function SystemType(const ATypeInfo: TResolvedSymbol): Boolean;
  begin
    Result := ATypeInfo.Builtin or SameText(ATypeInfo.UnitName, 'System');
  end;

  /// <summary>Indizierter Zugriff auf einen String (S[1])? Sein Typ ist dann ein Zeichen, nicht der String.
  /// </summary>
  function StringElement(ANode: TSyntaxNode; out ABase: TResolvedSymbol; out ABaseType: TResolvedSymbol): Boolean;
  begin
    Result := (ANode.Kind = TSyntaxKind.IndexAccess) and (ANode.ChildCount = 2) and
      mScope.SureType(Unwrapped(ANode[0]), ABase, ABaseType) and SystemType(ABaseType) and
      (KindOf(ABaseType.Name) <> TStringTypeKind.None);
  end;

  /// <summary>Stringart des Ausdrucks ANode mit sicher bekanntem eingebautem Typ; ADisplay ist der Typname.
  /// AWritable: nur Variablen, Felder und Properties (Ziel einer Zuweisung).</summary>
  function ExpressionKind(ANode: TSyntaxNode; AWritable: Boolean; out ADisplay: string): TStringTypeKind;
  var
    mNode: TSyntaxNode;
    mSymbol, mTypeInfo, mBase, mBaseType: TResolvedSymbol;
    mKinds: set of TIndexSymbolKind;
  begin
    Result := TStringTypeKind.None;
    ADisplay := '';
    mNode := Unwrapped(ANode);
    if (mNode = nil) or StringElement(mNode, mBase, mBaseType) then
      Exit;
    if AWritable then
      mKinds := [TIndexSymbolKind.Variable, TIndexSymbolKind.Field, TIndexSymbolKind.Property_]
    else
      mKinds := [TIndexSymbolKind.Variable, TIndexSymbolKind.Field, TIndexSymbolKind.Property_,
        TIndexSymbolKind.Method, TIndexSymbolKind.Routine, TIndexSymbolKind.Constant];
    if not mScope.SureType(mNode, mSymbol, mTypeInfo) or mSymbol.IsType or not (mSymbol.SymbolKind in mKinds) or
      not SystemType(mTypeInfo) then
      Exit;
    Result := KindOf(mTypeInfo.Name);
    ADisplay := mTypeInfo.Name;
  end;

  /// <summary>Wert eines konstanten String-Ausdrucks aus Literalen und + ; False für anderes.</summary>
  function ConstantString(ANode: TSyntaxNode; out AValue: string): Boolean;
  var
    mNode: TSyntaxNode;
    mLeft, mRight: string;
  begin
    AValue := '';
    mNode := Unwrapped(ANode);
    if mNode = nil then
      Exit(False);
    case mNode.Kind of
      TSyntaxKind.Literal:
        Result := (StartsStr('''', mNode.Name) or StartsStr('#', mNode.Name)) and
          TFormatString.LiteralValue(NodeText(mNode), AValue);
      TSyntaxKind.BinaryExpr:
        begin
          Result := (mNode.Name = '+') and (mNode.ChildCount = 2) and ConstantString(mNode[0], mLeft) and
            ConstantString(mNode[1], mRight);
          if Result then
            AValue := mLeft + mRight;
        end;
    else
      Result := False;
    end;
  end;

  /// <summary>Konstante mit Zeichen, die die Codepage nicht kennt, an einen Ansi-String (W1062 mit W1058).
  /// </summary>
  procedure CheckConstant(AValue: TSyntaxNode; const ATargetDisplay: string);
  var
    mText, mCodes: string;
    mChar: Char;
    mLost: Boolean;
    mWide, mLoss: TRuleWarnState;
  begin
    if (mCodePage <> cDefaultCodePage) or not ConstantString(AValue, mText) then
      Exit;
    mLost := False;
    for mChar in mText do
      if LostIn1252(mChar) then
      begin
        mLost := True;
        Break;
      end;
    if not mLost then
      Exit;
    mLoss := StateOf('W1058', AValue);
    mWide := StateOf('W1062', AValue);
    if TRuleWarnSwitches.Reported(mLoss) and TRuleWarnSwitches.Reported(mWide) then
      mCodes := 'W1058 und W1062'
    else if TRuleWarnSwitches.Reported(mWide) then
      mCodes := 'W1062'
    else if TRuleWarnSwitches.Reported(mLoss) then
      mCodes := 'W1058'
    else
      Exit;
    if (mLoss = TRuleWarnState.AsError) or (mWide = TRuleWarnState.AsError) then
      AReport.AddWithSeverity(TTextRange.Create(AValue.StartPos, AValue.EndPos), Format('%s enthält Zeichen, die ' +
        'es in der ANSI-Codepage %d nicht gibt; die Zuweisung an %s macht daraus ''?'' (wie %s).',
        [ValueText(AValue), mCodePage, ATargetDisplay, mCodes]), TRuleSeverity.Error, nil)
    else
      AReport.Add(TTextRange.Create(AValue.StartPos, AValue.EndPos), Format('%s enthält Zeichen, die es in der ' +
        'ANSI-Codepage %d nicht gibt; die Zuweisung an %s macht daraus ''?'' (wie %s).', [ValueText(AValue),
        mCodePage, ATargetDisplay, mCodes]), TRuleConfidence.Medium);
  end;

  /// <summary>Wert AValue an ein Ziel vom Typ ATargetDisplay der Art ATarget; AWhere beschreibt das Ziel
  /// ("die Zuweisung an S", "die Übergabe an Ausgeben").</summary>
  procedure CheckImplicit(AValue: TSyntaxNode; ATarget: TStringTypeKind; const ATargetDisplay, AWhere: string);
  var
    mSourceDisplay, mCode, mMessage: string;
    mSource: TStringTypeKind;
    mFix: TRuleFix;
  begin
    if ATarget = TStringTypeKind.Ansi then
      CheckConstant(AValue, ATargetDisplay);
    mSource := ExpressionKind(AValue, False, mSourceDisplay);
    mCode := ConversionCode(mSource, ATarget, False);
    if mCode = '' then
      Exit;
    if mCode = 'W1058' then
      mMessage := Format('%s ist %s; %s kann Zeichen verlieren (wie W1058).', [ValueText(AValue), mSourceDisplay,
        AWhere])
    else
      mMessage := Format('%s ist %s; %s wandelt implizit um (wie W1057).', [ValueText(AValue), mSourceDisplay,
        AWhere]);
    mFix := TRuleFix.Create(Format('Ausdrücklich in %s umwandeln', [ATargetDisplay]),
      [TTextEdit.Create(TTextRange.Create(AValue.StartPos, AValue.EndPos), Format('%s(%s)', [ATargetDisplay,
      NodeText(AValue)]))]);
    Report(mCode, AValue, mMessage, TRuleConfidence.High, [mFix]);
  end;

  procedure CheckAssignment(ANode: TSyntaxNode);
  var
    mTargetDisplay: string;
    mTarget: TStringTypeKind;
    mBase, mBaseType: TResolvedSymbol;
  begin
    if ANode.ChildCount <> 2 then
      Exit;
    // S[1] := 'x' (W1068): nur Variablen und Felder vom Typ string, keine Properties mit Index.
    if StringElement(Unwrapped(ANode[0]), mBase, mBaseType) then
    begin
      if (mBase.SymbolKind in [TIndexSymbolKind.Variable, TIndexSymbolKind.Field]) and
        MatchText(mBaseType.Name, ['string', 'UnicodeString']) then
        Report('W1068', ANode[0], Format('Zeichen von %s direkt geändert; das wird möglicherweise künftig nicht ' +
          'mehr unterstützt (wie W1068).', [NodeText(Unwrapped(ANode[0])[0])]), TRuleConfidence.High, nil);
      Exit;
    end;
    mTarget := ExpressionKind(ANode[0], True, mTargetDisplay);
    if mTarget <> TStringTypeKind.None then
      CheckImplicit(ANode[1], mTarget, mTargetDisplay, 'die Zuweisung an ' + NodeText(ANode[0]));
  end;

  procedure CheckInlineVar(ANode: TSyntaxNode);
  var
    mTypeName: string;
    mTypeInfo: TResolvedSymbol;
    mTarget: TStringTypeKind;
  begin
    if (ANode.ChildCount <> 2) or (ANode[0].Kind <> TSyntaxKind.TypeReference) or (Pos(',', ANode.Name) > 0) then
      Exit;
    mTypeName := NodeText(ANode[0]);
    mTarget := KindOf(mTypeName);
    if mTarget = TStringTypeKind.None then
      Exit;
    // Ein eigener Typ gleichen Namens verdeckt den aus System.
    mTypeInfo := mScope.Resolver.ResolveType(AContext.Tree, mScope.FileName, ANode[0].StartPos);
    if mTypeInfo.Found and not SystemType(mTypeInfo) then
      Exit;
    CheckImplicit(ANode[1], mTarget, mTypeName, 'die Zuweisung an ' + ANode.Name);
  end;

  procedure CheckCall(ACall: TSyntaxNode);
  var
    mSymbol, mTypeInfo: TResolvedSymbol;
    mTypeFound: Boolean;
    mParams: TArray<TSignatureParameter>;
    mIndex: Integer;
    mModifier: string;
    mTarget: TStringTypeKind;
  begin
    if (ACall.ChildCount < 2) or (ACall[0].Kind = TSyntaxKind.InheritedExpr) or
      not mScope.Resolver.NodeType(AContext.Tree, mScope.FileName, ACall, mSymbol, mTypeInfo, mTypeFound) or
      mSymbol.IsType or not (mSymbol.SymbolKind in [TIndexSymbolKind.Method, TIndexSymbolKind.Routine,
      TIndexSymbolKind.Constructor_]) or not mScope.DeclarationSure(mSymbol, ACall) or
      not RoutineParams(AContext, mSymbol, mParams) then
      Exit;
    // Passt die Zahl der Argumente nicht zum Kopf, ist es eine andere Routine (bzw. ein anderer Fehler).
    if (mSymbol.Signature <> '') and ((ACall.ChildCount - 1 < mSymbol.MinArgs) or
      (ACall.ChildCount - 1 > mSymbol.MaxArgs)) then
      Exit;
    for mIndex := 1 to ACall.ChildCount - 1 do
    begin
      if mIndex > Length(mParams) then
        Break;
      // var und out verlangen denselben Typ (E2033), das meldet eine andere Regel.
      mModifier := LowerCase(Trim(mParams[mIndex - 1].Modifier));
      // Mit Attribut ("[ref] var") zählt das letzte Wort.
      if Pos(' ', mModifier) > 0 then
        mModifier := Copy(mModifier, LastDelimiter(' ', mModifier) + 1, MaxInt);
      if (mModifier = 'var') or (mModifier = 'out') then
        Continue;
      mTarget := KindOf(mParams[mIndex - 1].TypeName);
      if mTarget <> TStringTypeKind.None then
        CheckImplicit(ACall[mIndex], mTarget, Trim(mParams[mIndex - 1].TypeName),
          Format('die Übergabe an %s (%s)', [mSymbol.Name, mParams[mIndex - 1].Name]));
    end;
  end;

  /// <summary>string(A) bzw. AnsiString(S): ausdrückliche Umwandlung (W1059, W1060).</summary>
  function CheckCast(ACall: TSyntaxNode): Boolean;
  var
    mCallee: TSyntaxNode;
    mTargetName, mSourceDisplay, mCode: string;
    mTarget, mSource: TStringTypeKind;
  begin
    Result := False;
    if ACall.ChildCount <> 2 then
      Exit;
    mCallee := ACall[0];
    if mCallee.Kind = TSyntaxKind.Identifier then
      mTargetName := mCallee.Name
    else if (mCallee.Kind = TSyntaxKind.MemberAccess) and (mCallee.ChildCount = 1) and
      (mCallee[0].Kind = TSyntaxKind.Identifier) and SameText(mCallee[0].Name, 'System') then
      mTargetName := mCallee.Name
    else
      Exit;
    mTarget := KindOf(mTargetName);
    if mTarget = TStringTypeKind.None then
      Exit;
    Result := True;
    mSource := ExpressionKind(ACall[1], False, mSourceDisplay);
    mCode := ConversionCode(mSource, mTarget, True);
    if mCode = 'W1060' then
      Report(mCode, ACall, Format('%s ist %s; die Umwandlung in %s kann Zeichen verlieren (wie W1060).',
        [ValueText(ACall[1]), mSourceDisplay, mTargetName]), TRuleConfidence.High, nil)
    else if mCode = 'W1059' then
      Report(mCode, ACall, Format('%s ist %s; ausdrückliche Umwandlung in %s (wie W1059).',
        [ValueText(ACall[1]), mSourceDisplay, mTargetName]), TRuleConfidence.High, nil);
  end;

  /// <summary>Mengenkonstruktor aus Zeichenliteralen bis #127 ('a', #9, 'a'..'z')?</summary>
  function AsciiCharSet(ASet: TSyntaxNode): Boolean;
  var
    mElement, mPart: TSyntaxNode;
    mIndex, mPartIndex: Integer;
    mValue: string;
  begin
    Result := (ASet.Kind = TSyntaxKind.SetConstructor) and (ASet.ChildCount > 0);
    for mIndex := 0 to ASet.ChildCount - 1 do
    begin
      if not Result then
        Exit;
      mElement := ASet[mIndex];
      if mElement.Kind = TSyntaxKind.RangeExpr then
        Result := mElement.ChildCount = 2
      else
        Result := mElement.Kind = TSyntaxKind.Literal;
      if not Result then
        Exit;
      for mPartIndex := 0 to mElement.ChildCount - 1 do
      begin
        mPart := mElement[mPartIndex];
        Result := Result and (mPart.Kind = TSyntaxKind.Literal) and ConstantString(mPart, mValue) and
          (Length(mValue) = 1) and (Ord(mValue[1]) <= 127);
      end;
      if mElement.Kind = TSyntaxKind.Literal then
        Result := ConstantString(mElement, mValue) and (Length(mValue) = 1) and (Ord(mValue[1]) <= 127);
    end;
  end;

  /// <summary>C in ['a'..'z'] mit C: Char (W1050); Korrektur CharInSet.</summary>
  procedure CheckSetMembership(ANode: TSyntaxNode);
  var
    mLeft: TSyntaxNode;
    mSymbol, mTypeInfo, mBase, mBaseType: TResolvedSymbol;
    mDisplay: string;
    mEdits: TArray<TTextEdit>;
    mUsesEdit: TTextEdit;
    mUsed: TArray<string>;
  begin
    if not SameText(ANode.Name, 'in') or (ANode.ChildCount <> 2) or not AsciiCharSet(Unwrapped(ANode[1])) then
      Exit;
    mLeft := Unwrapped(ANode[0]);
    if StringElement(mLeft, mBase, mBaseType) then
    begin
      // S[I]: nur Variablen, Felder und Konstanten; bei Properties wählt der Index einen Eintrag.
      if not (mBase.SymbolKind in [TIndexSymbolKind.Variable, TIndexSymbolKind.Field, TIndexSymbolKind.Constant]) or
        (KindOf(mBaseType.Name) <> TStringTypeKind.Unicode) then
        Exit;
      mDisplay := 'Char';
    end
    else
    begin
      if not mScope.SureType(mLeft, mSymbol, mTypeInfo) or mSymbol.IsType or not SystemType(mTypeInfo) or
        not MatchText(mTypeInfo.Name, ['Char', 'WideChar']) or not (mSymbol.SymbolKind in [TIndexSymbolKind.Variable,
        TIndexSymbolKind.Field, TIndexSymbolKind.Property_, TIndexSymbolKind.Method, TIndexSymbolKind.Routine,
        TIndexSymbolKind.Constant]) then
        Exit;
      mDisplay := mTypeInfo.Name;
    end;
    mEdits := [TTextEdit.Create(TTextRange.Create(ANode.StartPos, ANode.EndPos), Format('CharInSet(%s, %s)',
      [NodeText(ANode[0]), NodeText(ANode[1])]))];
    mUsed := TUsesClauses.UsedUnits(mScope.Tokens);
    if not TUsesClauses.IsUsed(mUsed, 'System.SysUtils', AContext.Namespaces) and
      not TUsesClauses.IsUsed(mUsed, 'SysUtils', AContext.Namespaces) then
    begin
      if TUsesClauses.AddUnit(mScope.Tokens, ANode.StartOffset, 'System.SysUtils',
        TTextLines.LineBreakOf(AContext.Text), mUsesEdit) then
        mEdits := mEdits + [mUsesEdit]
      else
        mEdits := nil;
    end;
    if mEdits = nil then
      Report('W1050', ANode, Format('%s ist %s; im Mengenausdruck wird das Zeichen auf ein Byte gekürzt ' +
        '(wie W1050).', [ValueText(ANode[0]), mDisplay]), TRuleConfidence.High, nil)
    else
      Report('W1050', ANode, Format('%s ist %s; im Mengenausdruck wird das Zeichen auf ein Byte gekürzt ' +
        '(wie W1050).', [ValueText(ANode[0]), mDisplay]), TRuleConfidence.High,
        [TRuleFix.Create('CharInSet verwenden', mEdits)]);
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    mIndex: Integer;
    mNode: TSyntaxNode;
    mPending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ARoot);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        case mNode.Kind of
          TSyntaxKind.AssignStatement:
            CheckAssignment(mNode);
          TSyntaxKind.InlineVar:
            CheckInlineVar(mNode);
          TSyntaxKind.Call:
            if not CheckCast(mNode) then
              CheckCall(mNode);
          TSyntaxKind.BinaryExpr:
            CheckSetMembership(mNode);
        else
          // Übrige Knoten bewusst ohne Wirkung.
        end;
        for mIndex := mNode.ChildCount - 1 downto 0 do
          mPending.Push(mNode[mIndex]);
      end;
    finally
      mPending.Free;
    end;
  end;

  /// <summary>{$H-} bzw. {$LONGSTRINGS OFF} irgendwo in der Datei: string ist dort ShortString.</summary>
  function ShortStrings: Boolean;
  var
    mToken: TPascalToken;
    mText: string;
  begin
    for mToken in AContext.Tree.Tokens do
      if mToken.Kind = TPascalTokenKind.Directive then
      begin
        mText := UpperCase(StringReplace(mToken.Text, ' ', '', [rfReplaceAll]));
        if ContainsStr(mText, '$H-') or ContainsStr(mText, ',H-') or ContainsStr(mText, '$LONGSTRINGSOFF') then
          Exit(True);
      end;
    Result := False;
  end;

var
  mVersion: Integer;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  mVersion := TLanguageFeatures.ParseVersion(AContext.DelphiVersion);
  if ((mVersion > 0) and (mVersion < TLanguageFeatures.ParseVersion(cUnicodeVersion))) or ShortStrings then
    Exit;
  mCodePage := TRuleOptions.Int(AContext.Options, 'ansiCodePage', cDefaultCodePage);
  mSwitches := TRuleWarnSwitches.Create(AContext);
  mScope := TTypedScope.Create(AContext);
  try
    Visit(AContext.Tree.Root);
  finally
    mScope.Free;
    mSwitches.Free;
  end;
end;

procedure RegisterStringConversionRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TStringConversionRule.Create);
end;

end.
