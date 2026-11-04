unit Atlas.Common.Rules.Builtin.FormatArgs;

// Formatstrings gegen ihre Argumente (#56, Gruppe „Fehler finden“):
//   format-args       Format, FmtStr, FormatBuf, StrFmt, StrLFmt, WideFormat,
//                     WideFmtStr, Exception.CreateFmt bzw. CreateFmtHelp,
//                     TStringBuilder.AppendFormat (Liste in Pascal.FormatRoutines,
//                     gemeinsam mit dem Parameter-Hint, #451) und die
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
  Atlas.Common.Pascal.FormatRoutines,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.TypedScope;

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

{ TFormatArgsRule }

function TFormatArgsRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(FormatArgsRuleId, TRuleSeverity.Error,
    'Formatstring passt nicht zu den Argumenten');
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

  /// <summary>Deklaration der Konstanten ASymbol in dieser Datei; nil, wenn sie anderswo steht.</summary>
  function ConstNode(const ASymbol: TResolvedSymbol): TSyntaxNode;
  var
    mPending: TStack<TSyntaxNode>;
    mNode: TSyntaxNode;
    mIndex: Integer;
  begin
    Result := nil;
    if not SameText(ASymbol.FileName, mScope.FileName) then
    begin
      Exit;
    end;
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(AContext.Tree.Root);
      while (Result = nil) and (mPending.Count > 0) do
      begin
        mNode := mPending.Pop;
        if (mNode.Kind = TSyntaxKind.ConstDecl) and SameText(mNode.Name, ASymbol.Name) and
          (mNode.StartPos.Line = ASymbol.SelectionRange.StartPos.Line) and (mNode.ChildCount > 0) then
        begin
          Result := mNode;
        end
        else
        begin
          for mIndex := mNode.ChildCount - 1 downto 0 do
          begin
            mPending.Push(mNode[mIndex]);
          end;
        end;
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
    begin
      Exit;
    end;
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
          begin
            Result := FormatValue(mDecl[mDecl.ChildCount - 1], ADepth + 1, AValue);
          end
          else
          begin
            Result := TFormatString.ConstantValue(mSymbol.Signature, AValue);
          end;
        end;
    else
      // Übrige Arten: nichts zu tun.
    end;
  end;

  /// <summary>Art des Typs ASymbol/AType nach dem Namen.</summary>
  function TypeClass(const AType: TResolvedSymbol): TFormatArgumentClass;
  begin
    Result := TFormatArgumentClass.Unknown;
    if MatchText(AType.Name, ['Variant', 'OleVariant']) then
    begin
      Result := TFormatArgumentClass.Variant_;
    end
    else if MatchText(AType.Name, cBoolTypes) then
    begin
      Result := TFormatArgumentClass.Bool;
    end
    else if MatchText(AType.Name, cIntegerTypes) then
    begin
      Result := TFormatArgumentClass.Integer_;
    end
    else if MatchText(AType.Name, cFloatTypes) then
    begin
      Result := TFormatArgumentClass.Float;
    end
    else if MatchText(AType.Name, cTextTypes) then
    begin
      Result := TFormatArgumentClass.Text;
    end
    else if MatchText(AType.Name, cCharTypes) then
    begin
      Result := TFormatArgumentClass.Character;
    end
    else if SameText(AType.Name, 'Pointer') then
    begin
      Result := TFormatArgumentClass.Pointer_;
    end
    else if not AType.Builtin and (AType.SymbolKind = TIndexSymbolKind.EnumType) then
    begin
      Result := TFormatArgumentClass.Enum;
    end
    else if not AType.Builtin and (AType.SymbolKind = TIndexSymbolKind.ClassType) and (AType.TypeParams = '') and
      not ContainsText(AType.Signature, 'class of') then
    begin
      Result := TFormatArgumentClass.Object_;
    end;
  end;

  /// <summary>Argument ohne Klammern; eine negative Zahl als ihr Literal.</summary>
  function Operand(ANode: TSyntaxNode): TSyntaxNode;
  begin
    Result := Unwrapped(ANode);
    if (Result.Kind = TSyntaxKind.UnaryExpr) and (Result.Name = '-') and (Result.ChildCount = 1) and
      (Unwrapped(Result[0]).Kind = TSyntaxKind.Literal) then
    begin
      Result := Unwrapped(Result[0]);
    end;
  end;

  /// <summary>Art eines Ausdrucks mit sicherem Typ, der selbst kein Typ ist.</summary>
  function ExpressionClass(ANode: TSyntaxNode; out ATypeName: string): TFormatArgumentClass;
  var
    mSymbol, mType: TResolvedSymbol;
  begin
    ATypeName := '';
    Result := TFormatArgumentClass.Unknown;
    if mScope.SureType(ANode, mSymbol, mType) and not mSymbol.IsType then
    begin
      ATypeName := mType.Name;
      Result := TypeClass(mType);
    end;
  end;

  /// <summary>Art des Bezeichners ANode mit sicherem Typ; False, wenn der Typ nicht sicher ist.</summary>
  function SureIdentifierClass(ANode: TSyntaxNode; out ATypeName: string; out AClass: TFormatArgumentClass): Boolean;
  var
    mSymbol, mType: TResolvedSymbol;
  begin
    ATypeName := '';
    AClass := TFormatArgumentClass.Unknown;
    Result := mScope.SureType(ANode, mSymbol, mType);
    if not Result or mSymbol.IsType then
    begin
      Exit;
    end;
    ATypeName := mType.Name;
    if mSymbol.SymbolKind = TIndexSymbolKind.EnumMember then
    begin
      AClass := TFormatArgumentClass.Enum;
    end
    else
    begin
      AClass := TypeClass(mType);
    end;
  end;

  /// <summary>Aufzählungswerte haben keinen deklarierten Typ, nur den umgebenden.</summary>
  function EnumMemberClass(const ASymbol, AType: TResolvedSymbol; ANode: TSyntaxNode;
    out ATypeName: string): TFormatArgumentClass;
  begin
    ATypeName := '';
    Result := TFormatArgumentClass.Unknown;
    if (ASymbol.SymbolKind <> TIndexSymbolKind.EnumMember) or not mScope.DeclarationSure(ASymbol, ANode) then
    begin
      Exit;
    end;
    ATypeName := AType.Name;
    if ATypeName = '' then
    begin
      ATypeName := ASymbol.Container;
    end;
    if ATypeName = '' then
    begin
      ATypeName := 'Aufzählungswert';
    end;
    Result := TFormatArgumentClass.Enum;
  end;

  /// <summary>Ohne Deklaration: True, False, nil.</summary>
  function ConstantClass(ANode: TSyntaxNode; out ATypeName: string): TFormatArgumentClass;
  begin
    ATypeName := '';
    Result := TFormatArgumentClass.Unknown;
    if MatchText(ANode.Name, ['True', 'False']) then
    begin
      ATypeName := 'Boolean';
      Result := TFormatArgumentClass.Bool;
    end
    else if SameText(ANode.Name, 'nil') then
    begin
      ATypeName := 'nil';
      Result := TFormatArgumentClass.Pointer_;
    end;
  end;

  /// <summary>Art des Arguments ANode und sein Typname für die Meldung.</summary>
  function ArgumentClass(ANode: TSyntaxNode; out ATypeName: string): TFormatArgumentClass;
  var
    mSymbol, mType: TResolvedSymbol;
    mFoundAny: Boolean;
  begin
    ATypeName := '';
    ANode := Operand(ANode);
    if ANode.Kind = TSyntaxKind.Literal then
    begin
      Result := TFormatString.LiteralClass(Raw(ANode), ATypeName);
    end
    else if ANode.Kind <> TSyntaxKind.Identifier then
    begin
      Result := ExpressionClass(ANode, ATypeName);
    end
    else if SureIdentifierClass(ANode, ATypeName, Result) then
    begin
      // Art steht fest.
    end
    else if mScope.Resolver.NodeType(AContext.Tree, mScope.FileName, ANode, mSymbol, mType, mFoundAny) then
    begin
      Result := EnumMemberClass(mSymbol, mType, ANode, ATypeName);
    end
    else
    begin
      Result := ConstantClass(ANode, ATypeName);
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
  function Advice(AClass: TFormatArgumentClass; const AArgument: string): string;
  begin
    case AClass of
      TFormatArgumentClass.Enum:
        Result := Format(' Ord(%s) übergeben.', [AArgument]);
      TFormatArgumentClass.Bool:
        Result := Format(' BoolToStr(%s, True) übergeben.', [AArgument]);
    else
      Result := '';
    end;
  end;

  procedure CheckArgument(const ASpec: TFormatSpec; AType: Char; AArgument: TSyntaxNode);
  var
    mClass: TFormatArgumentClass;
    mTypeName, mShown: string;
  begin
    mClass := ArgumentClass(AArgument, mTypeName);
    if TFormatString.Fits(AType, mClass) then
    begin
      Exit;
    end;
    mShown := mScope.Text(Unwrapped(AArgument));
    if not StartsText('ein', mTypeName) and (mTypeName <> 'nil') then
    begin
      mTypeName := Format('vom Typ %s', [mTypeName]);
    end;
    if AType = '*' then
    begin
      AReport.Add(TTextRange.Create(AArgument.StartPos, AArgument.EndPos), Format('Das * in %s erwartet %s, %s ist ' +
        '%s: EConvertError zur Laufzeit.', [ASpec.Text, Expected(AType), mShown, mTypeName]), TRuleConfidence.High);
    end
    else
    begin
      AReport.Add(TTextRange.Create(AArgument.StartPos, AArgument.EndPos), Format('%s erwartet %s, %s ist %s: ' +
        'EConvertError zur Laufzeit.%s', [ASpec.Text, Expected(AType), mShown, mTypeName, Advice(mClass, mShown)]),
        TRuleConfidence.High);
    end;
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

  /// <summary>Aufgelöst: Der voll qualifizierte Name eines Kandidaten entscheidet (eine eigene Methode Format
  /// bleibt still).</summary>
  function ResolvedRoutine(const ACandidates: TArray<TResolvedSymbol>; out AFormatIndex: Integer): Boolean;
  var
    mCandidate: TResolvedSymbol;
    mRoutine: TFormatRoutine;
  begin
    AFormatIndex := -1;
    for mCandidate in ACandidates do
    begin
      for mRoutine in mRoutines do
      begin
        if TFormatRoutines.SameTail(mRoutine.Name, mCandidate.UnitName + '.' + mCandidate.QualifiedName) then
        begin
          AFormatIndex := mRoutine.FormatIndex;
          Exit(True);
        end;
      end;
    end;
    Result := False;
  end;

  /// <summary>Passt der geschriebene Name AWritten des Callee ACallee auf ARoutine: als Ende des Eintrags,
  /// Methoden auch über einen anderen Qualifizierer (EImport.CreateFmt)?</summary>
  function WrittenMatches(const ARoutine: TFormatRoutine; ACallee: TSyntaxNode; const AWritten: string): Boolean;
  begin
    Result := EndsText('.' + AWritten, ARoutine.Name) or SameText(AWritten, ARoutine.Name);
    Result := Result or (ARoutine.IsMethod and (ACallee.Kind = TSyntaxKind.MemberAccess) and
      EndsText('.' + ACallee.Name, ARoutine.Name));
  end;

  /// <summary>Nicht aufgelöst (RTL nicht im Index): geschriebener Name. Writer.Format bleibt still: Format ist
  /// keine Methode.</summary>
  function WrittenRoutine(ACallee: TSyntaxNode; out AFormatIndex: Integer): Boolean;
  var
    mRoutine: TFormatRoutine;
    mWritten: string;
  begin
    AFormatIndex := -1;
    mWritten := mScope.Text(ACallee);
    for mRoutine in mRoutines do
    begin
      if WrittenMatches(mRoutine, ACallee, mWritten) then
      begin
        AFormatIndex := mRoutine.FormatIndex;
        Exit(True);
      end;
    end;
    Result := False;
  end;

  /// <summary>Ist der Aufruf mit Callee ACallee eine Formatroutine? AFormatIndex: Position des Formatstrings
  /// ohne Argumentliste [...] (-1 unbekannt).</summary>
  function IsFormatRoutine(ACallee: TSyntaxNode; out AFormatIndex: Integer): Boolean;
  var
    mCandidates: TArray<TResolvedSymbol>;
  begin
    AFormatIndex := -1;
    if not (ACallee.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) or
      (ACallee.FindChild(TSyntaxKind.GenericArgs) <> nil) then
    begin
      Exit(False);
    end;
    mCandidates := mScope.Resolver.CallCandidates(AContext.Tree, mScope.FileName, ACallee);
    if mCandidates <> nil then
    begin
      Result := ResolvedRoutine(mCandidates, AFormatIndex);
    end
    else
    begin
      Result := WrittenRoutine(ACallee, AFormatIndex);
    end;
  end;

  /// <summary>Formatstring und Argumentliste des Aufrufs ANode. Bekannte Stelle des Formatstrings zuerst
  /// (FormatBuf: Puffer und Längen davor, die Länge direkt vor der Liste), sonst das Argument vor der Liste.
  /// AList: nil ohne Liste.</summary>
  function FindArguments(ANode: TSyntaxNode; AFormatIndex: Integer; out AFormatNode, AList: TSyntaxNode): Boolean;
  var
    mIndex: Integer;
  begin
    AList := nil;
    AFormatNode := nil;
    if (AFormatIndex >= 0) and (AFormatIndex + 1 < ANode.ChildCount) then
    begin
      AFormatNode := ANode[AFormatIndex + 1];
    end;
    for mIndex := 2 to ANode.ChildCount - 1 do
    begin
      if Unwrapped(ANode[mIndex]).Kind = TSyntaxKind.SetConstructor then
      begin
        AList := Unwrapped(ANode[mIndex]);
        if AFormatNode = nil then
        begin
          AFormatNode := ANode[mIndex - 1];
        end;
        Break;
      end;
    end;
    Result := AFormatNode <> nil;
  end;

  /// <summary>Meldet die erste ungültige Angabe im Formatstring an AFormatNode; True, wenn es eine gibt.
  /// </summary>
  function ReportedInvalid(const AFormat: TFormatString; AFormatNode: TSyntaxNode): Boolean;
  var
    mSpec: TFormatSpec;
  begin
    for mSpec in AFormat.Specs do
    begin
      if mSpec.Kind <> TFormatSpecKind.Valid then
      begin
        AReport.Add(TTextRange.Create(AFormatNode.StartPos, AFormatNode.EndPos), InvalidMessage(mSpec),
          TRuleConfidence.High);
        Exit(True);
      end;
    end;
    Result := False;
  end;

  /// <summary>Enthält die Liste einen Bereich (a..b)? Dann ist die Zahl der Argumente unbekannt.</summary>
  function HasRange(AList: TSyntaxNode): Boolean;
  var
    mIndex: Integer;
  begin
    for mIndex := 0 to AList.ChildCount - 1 do
    begin
      if AList[mIndex].Kind = TSyntaxKind.RangeExpr then
      begin
        Exit(True);
      end;
    end;
    Result := False;
  end;

  /// <summary>Zu wenige oder überzählige Argumente melden; False bei zu wenigen.</summary>
  function CheckCount(const AFormat: TFormatString; AList: TSyntaxNode): Boolean;
  var
    mArgs, mNeeded: Integer;
  begin
    mArgs := AList.ChildCount;
    mNeeded := AFormat.ArgumentCount;
    Result := mArgs >= mNeeded;
    if not Result then
    begin
      AReport.Add(TTextRange.Create(AList.StartPos, AList.EndPos), Format('Der Formatstring braucht %d Argumente, ' +
        'die Liste hat %d: EConvertError zur Laufzeit.', [mNeeded, mArgs]), TRuleConfidence.High);
    end
    else if (mArgs > mNeeded) and not AFormat.HasExplicitIndex then
    begin
      AReport.Add(TTextRange.Create(AList[mNeeded].StartPos, AList[mNeeded].EndPos), Format('Argument %d (%s) ' +
        'kommt im Formatstring nicht vor und wird nicht ausgegeben.', [mNeeded + 1, mScope.Text(AList[mNeeded])]),
        TRuleConfidence.Medium);
    end;
  end;

  procedure CheckArguments(const AFormat: TFormatString; AList: TSyntaxNode);
  var
    mSpec: TFormatSpec;
  begin
    for mSpec in AFormat.Specs do
    begin
      if mSpec.WidthArgument >= 0 then
      begin
        CheckArgument(mSpec, '*', AList[mSpec.WidthArgument]);
      end;
      if mSpec.PrecisionArgument >= 0 then
      begin
        CheckArgument(mSpec, '*', AList[mSpec.PrecisionArgument]);
      end;
      if mSpec.Argument >= 0 then
      begin
        CheckArgument(mSpec, mSpec.TypeChar, AList[mSpec.Argument]);
      end;
    end;
  end;

  procedure CheckCall(ANode: TSyntaxNode);
  var
    mFormatIndex: Integer;
    mFormatNode, mList: TSyntaxNode;
    mValue: string;
    mFormat: TFormatString;
  begin
    if (ANode.ChildCount < 2) or not IsFormatRoutine(ANode[0], mFormatIndex) or
      not FindArguments(ANode, mFormatIndex, mFormatNode, mList) or not FormatValue(mFormatNode, 0, mValue) then
    begin
      Exit;
    end;
    mFormat := TFormatString.Parse(mValue);
    if ReportedInvalid(mFormat, mFormatNode) or (mList = nil) or (mFormat.ArgumentCount < 0) or
      HasRange(mList) then
    begin
      Exit;
    end;
    if CheckCount(mFormat, mList) then
    begin
      CheckArguments(mFormat, mList);
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

var
  mName: string;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mRoutines := TFormatRoutines.Defaults;
  for mName in TRuleOptions.Strings(AContext.Options, 'formatMethods', nil) do
  begin
    if Trim(mName) <> '' then
    begin
      mRoutines := mRoutines + [TFormatRoutines.Custom(mName, -1)];
    end;
  end;
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
