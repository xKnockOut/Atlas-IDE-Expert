unit Atlas.Common.Rules.Builtin.FormatArgs;

// Formatstrings gegen ihre Argumente (#56, Gruppe „Fehler finden“):
//   format-args       Format, FmtStr, WideFormat, WideFmtStr, Exception.CreateFmt
//                     bzw. CreateFmtHelp, TStringBuilder.AppendFormat und die
//                     Methoden der Option formatMethods (der Formatstring steht
//                     vor der Argumentliste [...]). Geprüft wird nur ein
//                     bekannter Formatstring: Literal, Verkettung von
//                     Literalen, const oder resourcestring aus der Datei oder
//                     dem Index (Pascal.FormatStrings zerlegt ihn). Gemeldet
//                     werden ungültige Platzhalter (%q, '%5' am Ende, %0: ohne
//                     Typ), zu wenige Argumente, ein Argument hinter dem
//                     letzten verwendeten (mittlere Konfidenz, nur ohne Index
//                     im Formatstring) und Argumente vom falschen Typ: %d %u %x
//                     nur Ganzzahlen, %e %f %g %n %m nur Gleitkommazahlen, %s
//                     Strings, Zeichen und Variants, %p Zeiger, "*" eine
//                     Ganzzahl; Variants passen überall. Boolean,
//                     Aufzählungswerte und Objekte passen zu keinem Typ außer
//                     (Objekte) %p. Typen nur, wenn sie sicher bekannt sind
//                     (TTypedScope), sonst keine Aussage. Alles davon löst zur
//                     Laufzeit EConvertError aus. Eigene Routinen mit dem Namen
//                     Format bleiben still, wenn die Namensauflösung sie findet.

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  FormatArgsRuleId = 'format-args';

type
  TFormatArgsRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Passt AName ("Unit.Typ.Methode", "Methode") zum Eintrag AEntry? Der kürzere Name muss das Ende
    /// des längeren ab einer Punktgrenze sein, ohne Groß-/Kleinschreibung.</summary>
    class function SameTail(const AEntry, AName: string): Boolean; static;
  end;

procedure RegisterFormatArgsRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.FormatStrings,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.TypedScope;

type
  /// <summary>Art eines Arguments im Sinn von TVarRec.</summary>
  TArgumentClass = (Unknown, Integer_, Float, Text, Character, Bool, Variant_, Enum, Object_, Pointer_);

  /// <summary>Formatroutine: voll qualifizierter Name, Position des Formatstrings, wenn die Argumentliste
  /// keine [...] ist (-1: unbekannt), und ob sie eine Methode ist (ohne Namensauflösung genügt dann der
  /// Methodenname hinter einem beliebigen Qualifizierer: EImport.CreateFmt, mBuilder.AppendFormat).</summary>
  TFormatRoutine = record
    Name: string;
    FormatIndex: Integer;
    IsMethod: Boolean;
  end;

const
  // Höchste Tiefe beim Auflösen von Konstanten aus Konstanten.
  cMaxDepth = 8;
  cIntegerTypes: array[0..21] of string = ('Integer', 'Cardinal', 'Int64', 'UInt64', 'NativeInt', 'NativeUInt',
    'Byte', 'Word', 'ShortInt', 'SmallInt', 'LongInt', 'LongWord', 'Int8', 'UInt8', 'Int16', 'UInt16', 'Int32',
    'UInt32', 'FixedInt', 'FixedUInt', 'DWORD', 'THandle');
  cFloatTypes: array[0..9] of string = ('Double', 'Single', 'Extended', 'Currency', 'Real', 'Comp', 'TDateTime',
    'TDate', 'TTime', 'Real48');
  cTextTypes: array[0..10] of string = ('string', 'UnicodeString', 'AnsiString', 'WideString', 'ShortString',
    'RawByteString', 'UTF8String', 'PChar', 'PAnsiChar', 'PWideChar', 'TCaption');
  cCharTypes: array[0..2] of string = ('Char', 'AnsiChar', 'WideChar');
  cBoolTypes: array[0..3] of string = ('Boolean', 'ByteBool', 'WordBool', 'LongBool');

function Routine(const AName: string; AFormatIndex: Integer; AIsMethod: Boolean): TFormatRoutine;
begin
  Result.Name := AName;
  Result.FormatIndex := AFormatIndex;
  Result.IsMethod := AIsMethod;
end;

function DefaultRoutines: TArray<TFormatRoutine>;
begin
  Result := TArray<TFormatRoutine>.Create(Routine('System.SysUtils.Format', 0, False),
    Routine('System.SysUtils.FmtStr', 1, False), Routine('System.SysUtils.WideFormat', 0, False),
    Routine('System.SysUtils.WideFmtStr', 1, False), Routine('System.SysUtils.Exception.CreateFmt', 0, True),
    Routine('System.SysUtils.Exception.CreateFmtHelp', 0, True),
    Routine('System.SysUtils.TStringBuilder.AppendFormat', 0, True));
end;

{ TFormatArgsRule }

function TFormatArgsRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(FormatArgsRuleId, TRuleSeverity.Error,
    'Formatstring passt nicht zu den Argumenten');
end;

class function TFormatArgsRule.SameTail(const AEntry, AName: string): Boolean;
begin
  Result := SameText(AEntry, AName) or EndsText('.' + AName, AEntry) or EndsText('.' + AEntry, AName);
end;

procedure TFormatArgsRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mScope: TTypedScope;
  mRoutines: TArray<TFormatRoutine>;

  /// <summary>Quelltext von ANode unverändert (Text() fasst Leerraum zusammen, auch in Literalen).</summary>
  function Raw(ANode: TSyntaxNode): string;
  begin
    Result := Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
  end;

  /// <summary>Wert eines Ausdrucks aus Literalen, die mit + verbunden sind (Text einer Signatur).</summary>
  function ExpressionValue(const AText: string; out AValue: string): Boolean;
  var
    mPos, mStart: Integer;
    mQuoted: Boolean;
    mPart: string;
  begin
    AValue := '';
    mQuoted := False;
    mStart := 1;
    for mPos := 1 to Length(AText) + 1 do
    begin
      if (mPos <= Length(AText)) and (AText[mPos] = '''') then
        mQuoted := not mQuoted;
      if (mPos > Length(AText)) or not mQuoted and (AText[mPos] = '+') then
      begin
        if not TFormatString.LiteralValue(Trim(Copy(AText, mStart, mPos - mStart)), mPart) then
          Exit(False);
        AValue := AValue + mPart;
        mStart := mPos + 1;
      end;
    end;
    Result := True;
  end;

  /// <summary>Wert einer Konstanten aus ihrer Signatur ("cFormat = 'Text'", "cFormat: string = 'Text'").</summary>
  function SignatureValue(const ASignature: string; out AValue: string): Boolean;
  var
    mEqual, mQuote: Integer;
  begin
    AValue := '';
    mEqual := Pos('=', ASignature);
    mQuote := Pos('''', ASignature);
    // Gekürzte Signatur bzw. "=" erst im Literal.
    if (mEqual = 0) or EndsStr('…', ASignature) or ((mQuote > 0) and (mQuote < mEqual)) then
      Exit(False);
    Result := ExpressionValue(Trim(Copy(ASignature, mEqual + 1, MaxInt)), AValue);
  end;

  /// <summary>Deklaration der Konstanten ASymbol in dieser Datei; nil, wenn sie anderswo steht.</summary>
  function ConstNode(const ASymbol: TResolvedSymbol): TSyntaxNode;
  var
    mPending: TStack<TSyntaxNode>;
    mNode: TSyntaxNode;
    mIndex: Integer;
  begin
    Result := nil;
    if not SameText(ASymbol.FileName, mScope.FileName) then
      Exit;
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(AContext.Tree.Root);
      while (Result = nil) and (mPending.Count > 0) do
      begin
        mNode := mPending.Pop;
        if (mNode.Kind = TSyntaxKind.ConstDecl) and SameText(mNode.Name, ASymbol.Name) and
          (mNode.StartPos.Line = ASymbol.SelectionRange.StartPos.Line) and (mNode.ChildCount > 0) then
          Result := mNode
        else
          for mIndex := mNode.ChildCount - 1 downto 0 do
            mPending.Push(mNode[mIndex]);
      end;
    finally
      mPending.Free;
    end;
  end;

  /// <summary>Wert des Formatstrings ANode: Literal, + aus Literalen, Konstante bzw. resourcestring (in dieser
  /// Datei auch aus anderen Konstanten zusammengesetzt).</summary>
  function FormatValue(ANode: TSyntaxNode; ADepth: Integer; out AValue: string): Boolean;
  var
    mDecl: TSyntaxNode;
    mLeft, mRight: string;
    mSymbol, mType: TResolvedSymbol;
    mFound: Boolean;
  begin
    AValue := '';
    Result := False;
    if ADepth > cMaxDepth then
      Exit;
    ANode := Unwrapped(ANode);
    case ANode.Kind of
      TSyntaxKind.Literal:
        Result := TFormatString.LiteralValue(Raw(ANode), AValue);
      TSyntaxKind.BinaryExpr:
        if (ANode.Name = '+') and (ANode.ChildCount = 2) and FormatValue(ANode[0], ADepth + 1, mLeft) and
          FormatValue(ANode[1], ADepth + 1, mRight) then
        begin
          AValue := mLeft + mRight;
          Result := True;
        end;
      TSyntaxKind.Identifier, TSyntaxKind.MemberAccess:
        if mScope.Resolver.NodeType(AContext.Tree, mScope.FileName, ANode, mSymbol, mType, mFound) and
          (mSymbol.SymbolKind = TIndexSymbolKind.Constant) and mScope.DeclarationSure(mSymbol, ANode) then
        begin
          mDecl := ConstNode(mSymbol);
          if mDecl <> nil then
            Result := FormatValue(mDecl[mDecl.ChildCount - 1], ADepth + 1, AValue)
          else
            Result := SignatureValue(mSymbol.Signature, AValue);
        end;
    end;
  end;

  /// <summary>Art des Typs ASymbol/AType nach dem Namen.</summary>
  function TypeClass(const AType: TResolvedSymbol): TArgumentClass;
  begin
    Result := TArgumentClass.Unknown;
    if MatchText(AType.Name, ['Variant', 'OleVariant']) then
      Result := TArgumentClass.Variant_
    else if MatchText(AType.Name, cBoolTypes) then
      Result := TArgumentClass.Bool
    else if MatchText(AType.Name, cIntegerTypes) then
      Result := TArgumentClass.Integer_
    else if MatchText(AType.Name, cFloatTypes) then
      Result := TArgumentClass.Float
    else if MatchText(AType.Name, cTextTypes) then
      Result := TArgumentClass.Text
    else if MatchText(AType.Name, cCharTypes) then
      Result := TArgumentClass.Character
    else if SameText(AType.Name, 'Pointer') then
      Result := TArgumentClass.Pointer_
    else if not AType.Builtin and (AType.SymbolKind = TIndexSymbolKind.EnumType) then
      Result := TArgumentClass.Enum
    else if not AType.Builtin and (AType.SymbolKind = TIndexSymbolKind.ClassType) and (AType.TypeParams = '') and
      not ContainsText(AType.Signature, 'class of') then
      Result := TArgumentClass.Object_;
  end;

  /// <summary>Art des Arguments ANode und sein Typname für die Meldung.</summary>
  function ArgumentClass(ANode: TSyntaxNode; out ATypeName: string): TArgumentClass;
  var
    mSymbol, mType: TResolvedSymbol;
    mText, mValue: string;
    mFoundAny: Boolean;
  begin
    ATypeName := '';
    Result := TArgumentClass.Unknown;
    ANode := Unwrapped(ANode);
    if (ANode.Kind = TSyntaxKind.UnaryExpr) and (ANode.Name = '-') and (ANode.ChildCount = 1) and
      (Unwrapped(ANode[0]).Kind = TSyntaxKind.Literal) then
      ANode := Unwrapped(ANode[0]);
    if ANode.Kind = TSyntaxKind.Literal then
    begin
      mText := Raw(ANode);
      if TFormatString.LiteralValue(mText, mValue) then
      begin
        ATypeName := 'ein String';
        if Length(mValue) = 1 then
          Exit(TArgumentClass.Character);
        Exit(TArgumentClass.Text);
      end;
      if (mText <> '') and CharInSet(mText[1], ['0'..'9', '$']) then
      begin
        ATypeName := 'eine Zahl';
        if (mText[1] <> '$') and (ContainsText(mText, '.') or ContainsText(mText, 'e')) then
          Exit(TArgumentClass.Float);
        Exit(TArgumentClass.Integer_);
      end;
      Exit;
    end;
    if ANode.Kind <> TSyntaxKind.Identifier then
    begin
      if mScope.SureType(ANode, mSymbol, mType) and not mSymbol.IsType then
      begin
        ATypeName := mType.Name;
        Result := TypeClass(mType);
      end;
      Exit;
    end;
    if mScope.SureType(ANode, mSymbol, mType) then
    begin
      if mSymbol.IsType then
        Exit;
      ATypeName := mType.Name;
      if mSymbol.SymbolKind = TIndexSymbolKind.EnumMember then
        Exit(TArgumentClass.Enum);
      Exit(TypeClass(mType));
    end;
    if mScope.Resolver.NodeType(AContext.Tree, mScope.FileName, ANode, mSymbol, mType, mFoundAny) then
    begin
      // Aufzählungswerte haben keinen deklarierten Typ, nur den umgebenden.
      if (mSymbol.SymbolKind = TIndexSymbolKind.EnumMember) and mScope.DeclarationSure(mSymbol, ANode) then
      begin
        ATypeName := mType.Name;
        if ATypeName = '' then
          ATypeName := mSymbol.Container;
        if ATypeName = '' then
          ATypeName := 'Aufzählungswert';
        Result := TArgumentClass.Enum;
      end;
      Exit;
    end;
    // Ohne Deklaration: True, False, nil.
    if MatchText(ANode.Name, ['True', 'False']) then
    begin
      ATypeName := 'Boolean';
      Result := TArgumentClass.Bool;
    end
    else if SameText(ANode.Name, 'nil') then
    begin
      ATypeName := 'nil';
      Result := TArgumentClass.Pointer_;
    end;
  end;

  /// <summary>Passt die Art AClass zum Typbuchstaben AType ('*' für Breite bzw. Genauigkeit)?</summary>
  function Fits(AType: Char; AClass: TArgumentClass): Boolean;
  begin
    if AClass in [TArgumentClass.Unknown, TArgumentClass.Variant_] then
      Exit(True);
    case AType of
      'd', 'u', 'x', '*':
        Result := AClass = TArgumentClass.Integer_;
      'e', 'f', 'g', 'n', 'm':
        Result := AClass = TArgumentClass.Float;
      's':
        Result := AClass in [TArgumentClass.Text, TArgumentClass.Character];
      'p':
        Result := AClass in [TArgumentClass.Pointer_, TArgumentClass.Object_];
    else
      Result := True;
    end;
  end;

  function Expected(AType: Char): string;
  begin
    case AType of
      'd', 'u', 'x':
        Result := 'eine Ganzzahl';
      'e', 'f', 'g', 'n', 'm':
        Result := 'eine Gleitkommazahl';
      's':
        Result := 'einen String, ein Zeichen oder einen Variant';
      'p':
        Result := 'einen Zeiger';
    else
      Result := 'eine Ganzzahl für Breite bzw. Genauigkeit';
    end;
  end;

  /// <summary>Vorschlag zur Meldung bei falschem Typ.</summary>
  function Advice(AClass: TArgumentClass; const AArgument: string): string;
  begin
    case AClass of
      TArgumentClass.Enum:
        Result := Format(' Ord(%s) übergeben.', [AArgument]);
      TArgumentClass.Bool:
        Result := Format(' BoolToStr(%s, True) übergeben.', [AArgument]);
    else
      Result := '';
    end;
  end;

  procedure CheckArgument(const ASpec: TFormatSpec; AType: Char; AArgument: TSyntaxNode);
  var
    mClass: TArgumentClass;
    mTypeName, mShown: string;
  begin
    mClass := ArgumentClass(AArgument, mTypeName);
    if Fits(AType, mClass) then
      Exit;
    mShown := mScope.Text(Unwrapped(AArgument));
    if not StartsText('ein', mTypeName) and (mTypeName <> 'nil') then
      mTypeName := Format('vom Typ %s', [mTypeName]);
    if AType = '*' then
      AReport.Add(TTextRange.Create(AArgument.StartPos, AArgument.EndPos), Format('Das * in %s erwartet %s, %s ist ' +
        '%s: EConvertError zur Laufzeit.', [ASpec.Text, Expected(AType), mShown, mTypeName]), TRuleConfidence.High)
    else
      AReport.Add(TTextRange.Create(AArgument.StartPos, AArgument.EndPos), Format('%s erwartet %s, %s ist %s: ' +
        'EConvertError zur Laufzeit.%s', [ASpec.Text, Expected(AType), mShown, mTypeName, Advice(mClass, mShown)]),
        TRuleConfidence.High);
  end;

  function InvalidMessage(const ASpec: TFormatSpec): string;
  begin
    case ASpec.Kind of
      TFormatSpecKind.UnknownType:
        Result := Format('Ungültiger Formatstring: In %s ist "%s" kein Typbuchstabe (d, u, e, f, g, n, m, p, s, x)',
          [ASpec.Text, Copy(ASpec.Text, Length(ASpec.Text), 1)]);
      TFormatSpecKind.Incomplete:
        Result := Format('Ungültiger Formatstring: %s am Ende ist unvollständig', [ASpec.Text]);
    else
      Result := Format('Ungültiger Formatstring: %s hat einen Index, aber keinen Typbuchstaben', [ASpec.Text]);
    end;
    Result := Result + ': EConvertError zur Laufzeit.';
  end;

  /// <summary>Ist der Aufruf mit Callee ACallee eine Formatroutine? AFormatIndex: Position des Formatstrings
  /// ohne Argumentliste [...] (-1 unbekannt).</summary>
  function IsFormatRoutine(ACallee: TSyntaxNode; out AFormatIndex: Integer): Boolean;
  var
    mCandidates: TArray<TResolvedSymbol>;
    mCandidate: TResolvedSymbol;
    mRoutine: TFormatRoutine;
    mQualified, mWritten: string;
  begin
    AFormatIndex := -1;
    Result := False;
    if not (ACallee.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) or
      (ACallee.FindChild(TSyntaxKind.GenericArgs) <> nil) then
      Exit;
    mWritten := mScope.Text(ACallee);
    mCandidates := mScope.Resolver.CallCandidates(AContext.Tree, mScope.FileName, ACallee);
    if mCandidates <> nil then
    begin
      // Aufgelöst: Der voll qualifizierte Name entscheidet (eine eigene Methode Format bleibt still).
      for mCandidate in mCandidates do
      begin
        mQualified := mCandidate.UnitName + '.' + mCandidate.QualifiedName;
        for mRoutine in mRoutines do
          if TFormatArgsRule.SameTail(mRoutine.Name, mQualified) then
          begin
            AFormatIndex := mRoutine.FormatIndex;
            Exit(True);
          end;
      end;
      Exit;
    end;
    // Nicht aufgelöst (RTL nicht im Index): geschriebener Name als Ende eines Eintrags, Methoden auch über
    // einen anderen Qualifizierer (EImport.CreateFmt). Writer.Format bleibt still: Format ist keine Methode.
    for mRoutine in mRoutines do
      if EndsText('.' + mWritten, mRoutine.Name) or SameText(mWritten, mRoutine.Name) or
        (mRoutine.IsMethod and (ACallee.Kind = TSyntaxKind.MemberAccess) and
        EndsText('.' + ACallee.Name, mRoutine.Name)) then
      begin
        AFormatIndex := mRoutine.FormatIndex;
        Exit(True);
      end;
  end;

  procedure CheckCall(ANode: TSyntaxNode);
  var
    mFormatIndex, mIndex, mArgs, mNeeded: Integer;
    mFormatNode, mList: TSyntaxNode;
    mValue: string;
    mFormat: TFormatString;
    mSpec: TFormatSpec;
  begin
    if (ANode.ChildCount < 2) or not IsFormatRoutine(ANode[0], mFormatIndex) then
      Exit;
    mList := nil;
    mFormatNode := nil;
    for mIndex := 2 to ANode.ChildCount - 1 do
      if Unwrapped(ANode[mIndex]).Kind = TSyntaxKind.SetConstructor then
      begin
        mList := Unwrapped(ANode[mIndex]);
        mFormatNode := ANode[mIndex - 1];
        Break;
      end;
    if (mFormatNode = nil) and (mFormatIndex >= 0) and (mFormatIndex + 1 < ANode.ChildCount) then
      mFormatNode := ANode[mFormatIndex + 1];
    if (mFormatNode = nil) or not FormatValue(mFormatNode, 0, mValue) then
      Exit;
    mFormat := TFormatString.Parse(mValue);
    for mSpec in mFormat.Specs do
      if mSpec.Kind <> TFormatSpecKind.Valid then
      begin
        AReport.Add(TTextRange.Create(mFormatNode.StartPos, mFormatNode.EndPos), InvalidMessage(mSpec),
          TRuleConfidence.High);
        Exit;
      end;
    mNeeded := mFormat.ArgumentCount;
    if (mList = nil) or (mNeeded < 0) then
      Exit;
    mArgs := mList.ChildCount;
    for mIndex := 0 to mArgs - 1 do
      if mList[mIndex].Kind = TSyntaxKind.RangeExpr then
        Exit;
    if mArgs < mNeeded then
    begin
      AReport.Add(TTextRange.Create(mList.StartPos, mList.EndPos), Format('Der Formatstring braucht %d Argumente, ' +
        'die Liste hat %d: EConvertError zur Laufzeit.', [mNeeded, mArgs]), TRuleConfidence.High);
      Exit;
    end;
    if (mArgs > mNeeded) and not mFormat.HasExplicitIndex then
      AReport.Add(TTextRange.Create(mList[mNeeded].StartPos, mList[mNeeded].EndPos), Format('Argument %d (%s) ' +
        'kommt im Formatstring nicht vor und wird nicht ausgegeben.', [mNeeded + 1, mScope.Text(mList[mNeeded])]),
        TRuleConfidence.Medium);
    for mSpec in mFormat.Specs do
    begin
      if mSpec.WidthArgument >= 0 then
        CheckArgument(mSpec, '*', mList[mSpec.WidthArgument]);
      if mSpec.PrecisionArgument >= 0 then
        CheckArgument(mSpec, '*', mList[mSpec.PrecisionArgument]);
      if mSpec.Argument >= 0 then
        CheckArgument(mSpec, mSpec.TypeChar, mList[mSpec.Argument]);
    end;
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
        if mNode.Kind = TSyntaxKind.Call then
          CheckCall(mNode);
        for mIndex := mNode.ChildCount - 1 downto 0 do
          mPending.Push(mNode[mIndex]);
      end;
    finally
      mPending.Free;
    end;
  end;

var
  mName: string;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  mRoutines := DefaultRoutines;
  for mName in TRuleOptions.Strings(AContext.Options, 'formatMethods', nil) do
    if Trim(mName) <> '' then
      mRoutines := mRoutines + [Routine(Trim(mName), -1, Pos('.', mName) > 0)];
  mScope := TTypedScope.Create(AContext);
  try
    Visit(AContext.Tree.Root);
  finally
    mScope.Free;
  end;
end;

procedure RegisterFormatArgsRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TFormatArgsRule.Create);
end;

end.
