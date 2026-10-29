unit Atlas.Common.Rules.Builtin.Directives;

// Regeln für Direktiven (#909):
//   compiler-warnings-disabled        (#972, Gruppe Robustheit und Muster)
//                                     {$WARNINGS OFF}, {$HINTS OFF}, {$WARN X
//                                     OFF}, {$R-}, {$Q-} und die langen Formen
//                                     ohne spätere Wiederherstellung (ON, +,
//                                     DEFAULT, ERROR oder {$POPOPT}); ein
//                                     Gegenstück im anderen Zweig desselben
//                                     {$IF} ist gewollt. Option allow.
// Gruppe Compiler vorab:
//   conditional-directive-unbalanced  Bedingte Direktiven unvollständig oder
//                                     unbekannt (#989): {$IF…} ohne {$ENDIF}
//                                     (E2095, E2280), {$ELSE}/{$ENDIF} ohne
//                                     Gegenstück (E2279), fehlendes oder
//                                     ungültiges Symbol (E2173), unbekannte
//                                     Direktive oder {$WARN}-Bezeichner (E1030,
//                                     vor Delphi 13 W1030),
//                                     {$POPOPT}/{$PUSHOPT} ohne Gegenstück
//                                     (W1078, W1079), ungültiger Wert für
//                                     {$ALIGN} (E2573).
//   directive-typo                    Unbekanntes Wort an der Stelle einer
//                                     Direktive nach einem Routinenkopf
//                                     (overide;) bzw. nach einer Property
//                                     (defualt;), mit Vorschlag (E2070, #1068).
//
// Die Regel liest die Direktiven-Token des ganzen Textes, auch in inaktiven
// Zweigen; dort zählt Delphi die Verschachtelung ebenfalls. Unbekannte Namen
// prüft sie nicht in Zweigen, deren Bedingung FPC abfragt ({$IFDEF FPC}{$MODE
// DELPHI}{$ENDIF}). {$PUSHOPT}/{$POPOPT} prüft sie nur, wenn keines davon in
// einem bedingten Zweig steht.
//
// directive-typo liest die Directive-Knoten des Syntaxbaums: Der Parser legt
// sie auch für unbekannte Wörter mit ';' dahinter an. Methodenzuordnungen
// (procedure IFoo.Bar = Baz;) übergeht sie (#1325). In Zweigen, deren
// Bedingung FPC abfragt, bleibt sie still (FPC kennt weitere Direktiven wie
// nostackframe).

interface

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  ConditionalDirectiveUnbalancedRuleId = 'conditional-directive-unbalanced';
  DirectiveTypoRuleId = 'directive-typo';
  CompilerWarningsDisabledRuleId = 'compiler-warnings-disabled';

type
  TConditionalDirectiveUnbalancedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TDirectiveTypoRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TCompilerWarningsDisabledRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterDirectiveRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.ConditionalBranches,
  Atlas.Common.Pascal.DirectiveNames,
  Atlas.Common.Pascal.LanguageFeatures,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Text.Fuzzy,
  Atlas.Common.Rules.Options,
  Atlas.Text.Lines;

const
  /// <summary>BDS-Nummer von Delphi 13: ab hier ist eine unbekannte Direktive ein Fehler (E1030, #1382).</summary>
  Delphi13 = '37.0';

type
  /// <summary>Offenes {$IF…} mit seiner Kette aus {$ELSEIF}/{$ELSE}.</summary>
  TOpenConditional = record
    /// <summary>Index der öffnenden Direktive in den Token.</summary>
    Opening: Integer;
    /// <summary>Index der letzten Direktive der Kette.</summary>
    Last: Integer;
    Name: string;
    /// <summary>Bedingung für die Meldung, z. B. DEBUG oder not DEBUG.</summary>
    Condition: string;
    HadElse: Boolean;
    /// <summary>Fragt diese oder eine umschließende Kette FPC ab?</summary>
    Fpc: Boolean;
  end;

/// <summary>Leerraum zu einem Zeichen zusammengefasst, höchstens AMax Zeichen.</summary>
function Compact(const AText: string; AMax: Integer): string;
var
  Ch: Char;
  Space: Boolean;
begin
  Result := '';
  Space := False;
  for Ch in Trim(AText) do
    if CharInSet(Ch, [' ', #9, #10, #13]) then
      Space := True
    else
    begin
      if Space then
        Result := Result + ' ';
      Space := False;
      Result := Result + Ch;
    end;
  if Length(Result) > AMax then
    Result := Copy(Result, 1, AMax - 1) + '…';
end;

/// <summary>Erstes Wort bis Leerraum oder Komma.</summary>
function FirstWord(const AText: string): string;
var
  Index: Integer;
begin
  Index := 1;
  while (Index <= Length(AText)) and not CharInSet(AText[Index], [' ', #9, #10, #13, ',']) do
    Inc(Index);
  Result := Copy(AText, 1, Index - 1);
end;

/// <summary>Kommt ein Bezeichner vor, der mit FPC beginnt (FPC, FPC_FULLVERSION)?</summary>
function MentionsFpc(const AText: string): Boolean;
var
  Index, Start: Integer;
begin
  Index := 1;
  while Index <= Length(AText) do
  begin
    if CharInSet(AText[Index], ['A'..'Z', 'a'..'z', '_']) then
    begin
      Start := Index;
      while (Index <= Length(AText)) and CharInSet(AText[Index], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
        Inc(Index);
      if StartsText('FPC', Copy(AText, Start, Index - Start)) then
        Exit(True);
    end
    else
      Inc(Index);
  end;
  Result := False;
end;

/// <summary>Ersatz in der Schreibweise des Originals: groß bleibt groß, sonst klein.</summary>
function LikeOriginal(const AOriginal, AReplacement: string): string;
begin
  if AOriginal = UpperCase(AOriginal) then
    Result := UpperCase(AReplacement)
  else
    Result := LowerCase(AReplacement);
end;

{ TConditionalDirectiveUnbalancedRule }

function TConditionalDirectiveUnbalancedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(ConditionalDirectiveUnbalancedRuleId, TRuleSeverity.Error,
    'Bedingte Direktiven unvollständig oder unbekannt');
end;

procedure TConditionalDirectiveUnbalancedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Stack: TArray<TOpenConditional>;
  Options: TArray<Integer>;
  OptionInBranch: Boolean;
  LineBreak, mUnknownCode: string;

  function RangeOf(AIndex: Integer): TTextRange;
  begin
    Result := TTextRange.Create(Tokens[AIndex].StartPos, Tokens[AIndex].EndPos);
  end;

  function InFpcBranch: Boolean;
  begin
    Result := (Stack <> nil) and Stack[High(Stack)].Fpc;
  end;

  /// <summary>Korrektur, die das Wort AWord (ab Zeichen AFrom der Direktive) durch AReplacement in seiner
  /// Schreibweise ersetzt; AShown steht im Titel.</summary>
  function ReplaceFix(AIndex: Integer; const AWord, AReplacement, AShown: string; AFrom: Integer;
    out AFix: TRuleFix): Boolean;
  var
    At: Integer;
    Start: TTextPosition;
  begin
    AFix := Default(TRuleFix);
    At := PosEx(AWord, Tokens[AIndex].Text, AFrom);
    Result := (At > 0) and (Tokens[AIndex].StartPos.Line = Tokens[AIndex].EndPos.Line);
    if not Result then
      Exit;
    Start := TTextPosition.Create(Tokens[AIndex].StartPos.Line, Tokens[AIndex].StartPos.Character + At - 1);
    AFix := TRuleFix.Create(Format('Tippfehler korrigieren: %s', [AShown]),
      [TRuleEdit.Create(TTextRange.Create(Start, TTextPosition.Create(Start.Line, Start.Character + Length(AWord))),
      LikeOriginal(AWord, AReplacement))]);
  end;

  /// <summary>Entfernt die Direktive AIndex, steht sie allein in der Zeile, mitsamt der Zeile.</summary>
  function RemoveFix(AIndex: Integer; const ATitle: string): TRuleFix;
  var
    Line: Integer;
    Alone: Boolean;
  begin
    Line := Tokens[AIndex].StartPos.Line;
    Alone := Tokens[AIndex].EndPos.Line = Line;
    if Alone and (AIndex > 0) then
      Alone := Tokens[AIndex - 1].EndPos.Line < Line;
    if Alone and (AIndex < High(Tokens)) then
      Alone := Tokens[AIndex + 1].StartPos.Line > Line;
    if Alone then
      Result := TRuleFix.Create(ATitle, [TRuleEdit.Create(TTextRange.Create(Line, 0, Line + 1, 0), '')])
    else
      Result := TRuleFix.Create(ATitle, [TRuleEdit.Create(RangeOf(AIndex), '')]);
  end;

  /// <summary>{$ENDIF} vor der ersten Leerzeile hinter der Kette; False ohne Leerzeile.</summary>
  function EndifFix(const AOpen: TOpenConditional; out AFix: TRuleFix): Boolean;
  var
    Index, Line: Integer;
  begin
    AFix := Default(TRuleFix);
    for Index := AOpen.Last + 1 to High(Tokens) do
      if Tokens[Index].StartPos.Line > Tokens[Index - 1].EndPos.Line + 1 then
      begin
        Line := Tokens[Index - 1].EndPos.Line;
        AFix := TRuleFix.Create(Format('{$ENDIF} nach Zeile %d ergänzen', [Line + 1]),
          [TRuleEdit.Create(TTextRange.Create(Line + 1, 0, Line + 1, 0),
          StringOfChar(' ', Tokens[AOpen.Opening].StartPos.Character) + '{$ENDIF}' + LineBreak)]);
        Exit(True);
      end;
    Result := False;
  end;

  procedure Stray(AIndex: Integer; const AName: string);
  begin
    AReport.Add(RangeOf(AIndex), Format('{$%s} ohne passendes {$IF…} (wie E2279).', [AName]), TRuleConfidence.High,
      [RemoveFix(AIndex, Format('Überzähliges {$%s} entfernen', [AName]))]);
  end;

  procedure CheckSymbol(AIndex: Integer; const AName, ARest: string);
  var
    Symbol: string;
  begin
    Symbol := FirstWord(ARest);
    if Symbol = '' then
      AReport.Add(RangeOf(AIndex), Format('{$%s} ohne Symbol (wie E2173).', [AName]), TRuleConfidence.High)
    else if not IsValidIdent(Symbol) then
      AReport.Add(RangeOf(AIndex), Format('%s ist kein gültiges Symbol für {$%s} (wie E2173).', [Symbol, AName]),
        TRuleConfidence.High);
  end;

  procedure CheckAlignValue(AIndex: Integer; const AValue: string; ALong: Boolean);
  begin
    if AValue = '' then
      Exit;
    if MatchText(AValue, ['1', '2', '4', '8', '16']) then
      Exit;
    if ALong and MatchText(AValue, ['ON', 'OFF']) then
      Exit;
    if not ALong and not CharInSet(AValue[1], ['0'..'9']) then
      Exit;
    AReport.Add(RangeOf(AIndex), Format('Ungültiger Wert %s für {$ALIGN}; erlaubt sind ON, OFF, 1, 2, 4, 8 und 16 ' +
      '(wie E2573).', [AValue]), TRuleConfidence.High);
  end;

  procedure CheckShortSwitches(AIndex: Integer; const ABody: string);
  var
    Part: string;
  begin
    for Part in SplitString(ABody, ',') do
      if SameText(TDirectiveNames.LeadingName(Trim(Part)), 'A') then
        CheckAlignValue(AIndex, Trim(Copy(Trim(Part), 2, MaxInt)), False);
  end;

  procedure CheckUnknown(AIndex: Integer; const AName: string);
  var
    Closest: string;
    Fix: TRuleFix;
  begin
    if InFpcBranch or TDirectiveNames.IsDirective(AName) then
      Exit;
    Closest := TTextFuzzy.Closest(AName, TDirectiveNames.Directives);
    if (Closest <> '') and ReplaceFix(AIndex, AName, Closest, '{$' + Closest + '}', 1, Fix) then
      AReport.Add(RangeOf(AIndex), Format('Unbekannte Direktive {$%s}; gemeint ist wohl {$%s} (wie %s).',
        [AName, Closest, mUnknownCode]), TRuleConfidence.High, [Fix])
    else
      AReport.Add(RangeOf(AIndex), Format('Unbekannte Direktive {$%s} (wie %s).', [AName, mUnknownCode]),
        TRuleConfidence.High);
  end;

  /// <summary>AFrom: erstes Zeichen hinter WARN in der Direktive.</summary>
  procedure CheckWarn(AIndex, AFrom: Integer; const ARest: string);
  var
    Id, Closest: string;
    Fix: TRuleFix;
  begin
    Id := TDirectiveNames.LeadingName(ARest);
    if (Id = '') or InFpcBranch or TDirectiveNames.IsWarning(Id) then
      Exit;
    Closest := TTextFuzzy.Closest(Id, TDirectiveNames.Warnings);
    if (Closest <> '') and ReplaceFix(AIndex, Id, Closest, Closest, AFrom, Fix) then
      AReport.Add(RangeOf(AIndex), Format('Unbekannte Warnung %s in {$WARN}; gemeint ist wohl %s (wie %s).',
        [Id, Closest, mUnknownCode]), TRuleConfidence.High, [Fix])
    else
      AReport.Add(RangeOf(AIndex), Format('Unbekannte Warnung %s in {$WARN} (wie %s).', [Id, mUnknownCode]),
        TRuleConfidence.High);
  end;

  procedure Open(AIndex: Integer; const AName, ARest: string);
  var
    Item: TOpenConditional;
  begin
    Item.Opening := AIndex;
    Item.Last := AIndex;
    Item.Name := AName;
    Item.HadElse := False;
    Item.Fpc := InFpcBranch or MentionsFpc(ARest);
    if AName = 'IFNDEF' then
      Item.Condition := 'not ' + FirstWord(ARest)
    else if AName = 'IFDEF' then
      Item.Condition := FirstWord(ARest)
    else
      Item.Condition := Compact(ARest, 40);
    Stack := Stack + [Item];
  end;

  procedure Unclosed(const AItem: TOpenConditional; ATop: Boolean);
  var
    Code: string;
    Message: string;
    Fix: TRuleFix;
  begin
    Code := 'E2095';
    if AItem.Name = 'IF' then
      Code := 'E2280';
    Message := Format('%s wird nie geschlossen; der Rest der Datei hängt an %s (wie %s).',
      [Compact(Tokens[AItem.Opening].Text, 60), AItem.Condition, Code]);
    if ATop and EndifFix(AItem, Fix) then
      AReport.Add(RangeOf(AItem.Opening), Message, TRuleConfidence.High, [Fix])
    else
      AReport.Add(RangeOf(AItem.Opening), Message, TRuleConfidence.High);
  end;

  procedure Visit(AIndex: Integer);
  var
    Body, Name, Rest: string;
  begin
    Body := TDirectiveNames.Body(Tokens[AIndex].Text);
    Name := UpperCase(TDirectiveNames.LeadingName(Body));
    Rest := Trim(Copy(Body, Length(Name) + 1, MaxInt));
    if Name = '' then
      Exit;
    if (Name = 'IF') or (Name = 'IFDEF') or (Name = 'IFNDEF') or (Name = 'IFOPT') then
    begin
      if (Name = 'IFDEF') or (Name = 'IFNDEF') then
        CheckSymbol(AIndex, Name, Rest);
      Open(AIndex, Name, Rest);
    end
    else if (Name = 'ELSE') or (Name = 'ELSEIF') then
    begin
      if Stack = nil then
        Stray(AIndex, Name)
      else if Stack[High(Stack)].HadElse then
        AReport.Add(RangeOf(AIndex), Format('{$%s} nach {$ELSE} von %s aus Zeile %d (wie E2279).',
          [Name, Compact(Tokens[Stack[High(Stack)].Opening].Text, 60),
          Tokens[Stack[High(Stack)].Opening].StartPos.Line + 1]), TRuleConfidence.High)
      else
      begin
        Stack[High(Stack)].HadElse := Name = 'ELSE';
        Stack[High(Stack)].Last := AIndex;
        if MentionsFpc(Rest) then
          Stack[High(Stack)].Fpc := True;
      end;
    end
    else if (Name = 'ENDIF') or (Name = 'IFEND') then
    begin
      if Stack = nil then
        Stray(AIndex, Name)
      else
        SetLength(Stack, Length(Stack) - 1);
    end
    else if (Name = 'DEFINE') or (Name = 'UNDEF') then
      CheckSymbol(AIndex, Name, Rest)
    else if (Name = 'PUSHOPT') or (Name = 'POPOPT') then
    begin
      Options := Options + [AIndex];
      OptionInBranch := OptionInBranch or (Stack <> nil);
    end
    else if Name = 'ALIGN' then
      CheckAlignValue(AIndex, FirstWord(Rest), True)
    else if Name = 'WARN' then
      CheckWarn(AIndex, Pos(TDirectiveNames.LeadingName(Body), Tokens[AIndex].Text) + Length(Name), Rest)
    else if Length(Name) = 1 then
      CheckShortSwitches(AIndex, Body)
    else
      CheckUnknown(AIndex, TDirectiveNames.LeadingName(Body));
  end;

  procedure CheckOptionStack;
  var
    Pushes: TArray<Integer>;
    Index: Integer;
  begin
    if OptionInBranch then
      Exit;
    Pushes := nil;
    for Index in Options do
      if SameText(TDirectiveNames.LeadingName(TDirectiveNames.Body(Tokens[Index].Text)), 'PUSHOPT') then
        Pushes := Pushes + [Index]
      else if Pushes = nil then
        AReport.Add(RangeOf(Index), '{$POPOPT} ohne vorheriges {$PUSHOPT} (wie W1078).', TRuleConfidence.High)
      else
        SetLength(Pushes, Length(Pushes) - 1);
    for Index in Pushes do
      AReport.Add(RangeOf(Index), '{$PUSHOPT} ohne passendes {$POPOPT} (wie W1079).', TRuleConfidence.High);
  end;

var
  Index: Integer;
begin
  if AContext.Tree = nil then
    Exit;
  Tokens := AContext.Tree.Tokens;
  LineBreak := #10;
  if Pos(#13#10, AContext.Text) > 0 then
    LineBreak := #13#10;
  Stack := nil;
  Options := nil;
  OptionInBranch := False;
  // Delphi 13 meldet unbekannte Direktiven und {$WARN}-Bezeichner als Fehler E1030, ältere Versionen als W1030
  // (#1382).
  mUnknownCode := 'W1030';
  if TLanguageFeatures.IsAtLeast(AContext.DelphiVersion, Delphi13) then
    mUnknownCode := 'E1030';
  for Index := 0 to High(Tokens) do
    if Tokens[Index].Kind = TPascalTokenKind.Directive then
      Visit(Index);
  for Index := 0 to High(Stack) do
    Unclosed(Stack[Index], Index = High(Stack));
  CheckOptionStack;
end;

{ TDirectiveTypoRule }

function TDirectiveTypoRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(DirectiveTypoRuleId, TRuleSeverity.Error, 'Unbekannte Direktive (Tippfehler)');
end;

/// <summary>Offsets der Token in Zweigen, deren Bedingung (auch umschließend) FPC abfragt.</summary>
function FpcOffsets(const ATokens: TArray<TPascalToken>): TArray<Integer>;
var
  Token: TPascalToken;
  Stack: TArray<Boolean>;
  Body, Name, Rest: string;
  Fpc: Boolean;
begin
  Result := nil;
  Stack := nil;
  for Token in ATokens do
  begin
    Fpc := (Stack <> nil) and Stack[High(Stack)];
    if Token.Kind <> TPascalTokenKind.Directive then
    begin
      if Fpc then
        Result := Result + [Token.Offset];
      Continue;
    end;
    Body := TDirectiveNames.Body(Token.Text);
    Name := UpperCase(TDirectiveNames.LeadingName(Body));
    Rest := Copy(Body, Length(Name) + 1, MaxInt);
    if (Name = 'IF') or (Name = 'IFDEF') or (Name = 'IFNDEF') or (Name = 'IFOPT') then
      Stack := Stack + [Fpc or MentionsFpc(Rest)]
    else if (Name = 'ELSEIF') and (Stack <> nil) then
      Stack[High(Stack)] := Stack[High(Stack)] or MentionsFpc(Rest)
    else if ((Name = 'ENDIF') or (Name = 'IFEND')) and (Stack <> nil) then
      SetLength(Stack, Length(Stack) - 1);
  end;
end;

procedure TDirectiveTypoRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Fpc: TArray<Integer>;
begin
  if AContext.Tree = nil then
    Exit;
  Fpc := nil;
  if Pos('{$', AContext.Text) > 0 then
    Fpc := FpcOffsets(AContext.Tree.Tokens);
  AContext.Tree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      Word, Closest: string;
      Candidates: TArray<string>;
      Range: TTextRange;
      Offset: Integer;
    begin
      Result := True;
      if (ANode.Kind <> TSyntaxKind.Directive) or (ANode.Parent = nil) then
        Exit;
      // Nach einer Property steht nur default, nach Routinenköpfen eine der Direktiven.
      if ANode.Parent.Kind = TSyntaxKind.PropertyDecl then
        Candidates := ['default']
      // Methodenzuordnung "function IFoo.GetX = MyGetX;": "= MyGetX" ist keine Direktive (#1325).
      else if (ANode.Parent.Kind = TSyntaxKind.RoutineHeader) and ANode.Parent.IsMethodResolution then
        Exit
      else if ANode.Parent.Kind = TSyntaxKind.RoutineHeader then
        Candidates := TDirectiveNames.RoutineDirectives
      else
        Exit;
      if MatchText(ANode.Name, Candidates) then
        Exit;
      for Offset in Fpc do
        if Offset = ANode.StartOffset then
          Exit;
      Word := Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
      Range := TTextRange.Create(ANode.StartPos, ANode.EndPos);
      Closest := TTextFuzzy.Closest(Word, Candidates);
      if Closest <> '' then
      begin
        Closest := LikeOriginal(Word, Closest);
        AReport.Add(Range, Format('Unbekannte Direktive %s; gemeint ist %s (wie E2070).', [Word, Closest]),
          TRuleConfidence.High, [TRuleFix.Create(Format('Durch %s ersetzen', [Closest]),
          [TRuleEdit.Create(Range, Closest)])]);
      end
      else
        AReport.Add(Range, Format('Unbekannte Direktive %s (wie E2070).', [Word]), TRuleConfidence.High);
    end);
end;

{ TCompilerWarningsDisabledRule }

type
  /// <summary>Ein Schalter in einer Direktive: WARNINGS, HINTS, RANGECHECKS, OVERFLOWCHECKS, WARN:Name,
  /// PUSHOPT oder POPOPT.</summary>
  TCompilerSwitch = record
    Switch: string;
    /// <summary>So stand der Schalter da: R, RANGECHECKS, WARN usw.; bestimmt die Form der Wiederherstellung.
    /// </summary>
    Written: string;
    Off: Boolean;
  end;

  /// <summary>Ein ausgeschalteter Schalter und ob er wiederhergestellt wird.</summary>
  TSwitchOff = record
    Item: TCompilerSwitch;
    Token: Integer;
    Restored: Boolean;
  end;

/// <summary>Schalter der Direktive ADirective; leer bei allen anderen Direktiven, auch {$R *.dfm}.</summary>
function SwitchesOf(const ADirective: string): TArray<TCompilerSwitch>;
var
  Body, Name, Rest, Part: string;
  Item: TCompilerSwitch;
  Words, Parts: TArray<string>;
begin
  Result := nil;
  Body := TDirectiveNames.Body(ADirective);
  Name := UpperCase(TDirectiveNames.LeadingName(Body));
  Rest := UpperCase(Trim(Copy(Body, Length(Name) + 1, MaxInt)));
  Item := Default(TCompilerSwitch);
  Item.Written := Name;
  if MatchStr(Name, ['WARNINGS', 'HINTS', 'RANGECHECKS', 'OVERFLOWCHECKS']) then
  begin
    if (Rest <> 'ON') and (Rest <> 'OFF') then
      Exit;
    Item.Switch := Name;
    Item.Off := Rest = 'OFF';
    Result := [Item];
    Exit;
  end;
  if Name = 'WARN' then
  begin
    Words := Rest.Split([' ', #9], TStringSplitOptions.ExcludeEmpty);
    if (Length(Words) <> 2) or not MatchStr(Words[1], ['ON', 'OFF', 'ERROR', 'DEFAULT']) then
      Exit;
    Item.Switch := 'WARN:' + Words[0];
    Item.Off := Words[1] = 'OFF';
    Result := [Item];
    Exit;
  end;
  if (Name = 'PUSHOPT') or (Name = 'POPOPT') then
  begin
    Item.Switch := Name;
    Result := [Item];
    Exit;
  end;
  // Kurzschalter: {$R-}, {$Q+}, {$R-,Q-,O+}; {$R *.dfm} ist eine Ressource.
  Parts := Body.Split([',']);
  for Part in Parts do
    if (Length(Trim(Part)) <> 2) or not CharInSet(Trim(Part)[1], ['A'..'Z', 'a'..'z']) or
      not CharInSet(Trim(Part)[2], ['+', '-']) then
      Exit;
  for Part in Parts do
  begin
    Item := Default(TCompilerSwitch);
    Item.Written := UpperCase(Trim(Part)[1]);
    if Item.Written = 'R' then
      Item.Switch := 'RANGECHECKS'
    else if Item.Written = 'Q' then
      Item.Switch := 'OVERFLOWCHECKS'
    else
      Continue;
    Item.Off := Trim(Part)[2] = '-';
    Result := Result + [Item];
  end;
end;

/// <summary>Direktive, die AItem wieder einschaltet.</summary>
function RestoreText(const AItem: TCompilerSwitch): string;
begin
  if StartsStr('WARN:', AItem.Switch) then
    Result := Format('{$WARN %s DEFAULT}', [Copy(AItem.Switch, 6, MaxInt)])
  else if Length(AItem.Written) = 1 then
    Result := Format('{$%s+}', [AItem.Written])
  else
    Result := Format('{$%s ON}', [AItem.Written]);
end;

function SwitchMessage(const AItem: TCompilerSwitch): string;
begin
  if AItem.Switch = 'WARNINGS' then
    Result := 'WARNINGS bleibt bis zum Ende der Unit aus; alle späteren Warnungen fehlen.'
  else if AItem.Switch = 'HINTS' then
    Result := 'HINTS bleibt bis zum Ende der Unit aus; alle späteren Hinweise fehlen.'
  else if AItem.Switch = 'RANGECHECKS' then
    Result := 'Die Bereichsprüfung bleibt bis zum Ende der Unit aus; Überschreitungen fallen nicht mehr auf.'
  else if AItem.Switch = 'OVERFLOWCHECKS' then
    Result := 'Die Überlaufprüfung bleibt bis zum Ende der Unit aus; Überläufe fallen nicht mehr auf.'
  else
    Result := Format('Die Warnung %s bleibt bis zum Ende der Unit aus.', [Copy(AItem.Switch, 6, MaxInt)]);
end;

/// <summary>Steht AItem in der Liste allow (Warnungsname, WARNINGS, HINTS, R bzw. RANGECHECKS, Q bzw.
/// OVERFLOWCHECKS)?</summary>
function SwitchAllowed(const AItem: TCompilerSwitch; const AAllow: TArray<string>): Boolean;
begin
  if StartsStr('WARN:', AItem.Switch) then
    Result := MatchText(Copy(AItem.Switch, 6, MaxInt), AAllow)
  else
    Result := MatchText(AItem.Switch, AAllow) or ((AItem.Switch = 'RANGECHECKS') and MatchText('R', AAllow)) or
      ((AItem.Switch = 'OVERFLOWCHECKS') and MatchText('Q', AAllow));
end;

/// <summary>Folgt hinter dem Token AIndex noch Code außer dem abschließenden "end."?</summary>
function CodeFollows(const ATokens: TArray<TPascalToken>; AIndex: Integer): Boolean;
var
  Index: Integer;
begin
  Result := False;
  for Index := AIndex + 1 to High(ATokens) do
    if not (ATokens[Index].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) and
      not ATokens[Index].IsKeyword('end') and not ATokens[Index].IsSymbol('.') then
      Exit(True);
end;

/// <summary>Der nächste Block hinter AOffset: das erste Geschwister hinter der Direktive im innersten Knoten,
/// der sie umschließt; nil ohne oder wenn es ein ganzer Abschnitt wäre.</summary>
function NextBlock(ATree: TSyntaxTree; AOffset: Integer): TSyntaxNode;
var
  Node, Inner: TSyntaxNode;
  Index: Integer;
begin
  Result := nil;
  Node := ATree.Root;
  while Node <> nil do
  begin
    Inner := nil;
    for Index := 0 to Node.ChildCount - 1 do
      if (Node[Index].StartOffset <= AOffset) and (AOffset < Node[Index].EndOffset) then
      begin
        Inner := Node[Index];
        Break;
      end
      else if Node[Index].StartOffset >= AOffset then
      begin
        Result := Node[Index];
        Break;
      end;
    Node := Inner;
  end;
  if (Result <> nil) and (Result.Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection,
    TSyntaxKind.InitializationSection, TSyntaxKind.FinalizationSection]) then
    Result := nil;
end;

function TCompilerWarningsDisabledRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(CompilerWarningsDisabledRuleId, TRuleSeverity.Warning,
    'Compiler-Warnungen oder Prüfungen bis zum Ende der Unit abgeschaltet');
end;

procedure TCompilerWarningsDisabledRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Paths, Allow, Lines: TArray<string>;
  Offs: TArray<TSwitchOff>;
  Item: TCompilerSwitch;
  Index, Other, Line: Integer;
  Off: TSwitchOff;
  Deliberate: Boolean;
  Block: TSyntaxNode;
  Fixes: TArray<TRuleFix>;
  LineBreak, Indent: string;
begin
  // Die Schalter einer .dpk sind die Optionen des Packages, die die IDE dort pflegt.
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or (AContext.Tree.Root.Kind = TSyntaxKind.PackageFile) then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Offs := nil;
  for Index := 0 to High(Tokens) do
    if Tokens[Index].Kind = TPascalTokenKind.Directive then
      for Item in SwitchesOf(Tokens[Index].Text) do
        if Item.Switch = 'POPOPT' then
          // {$POPOPT} stellt alles wieder her, was seit {$PUSHOPT} umgestellt wurde.
          for Other := 0 to High(Offs) do
            Offs[Other].Restored := True
        else if Item.Off then
        begin
          Off := Default(TSwitchOff);
          Off.Item := Item;
          Off.Token := Index;
          Offs := Offs + [Off];
        end
        else
          for Other := 0 to High(Offs) do
            if Offs[Other].Item.Switch = Item.Switch then
              Offs[Other].Restored := True;
  if Offs = nil then
    Exit;
  Allow := TRuleOptions.Strings(AContext.Options, 'allow', nil);
  Paths := TConditionalBranches.Paths(Tokens);
  Lines := TTextLines.SplitLines(AContext.Text, LineBreak);
  for Off in Offs do
  begin
    if Off.Restored or SwitchAllowed(Off.Item, Allow) or not CodeFollows(Tokens, Off.Token) then
      Continue;
    // {$IFDEF DEBUG}{$R+}{$ELSE}{$R-}{$ENDIF}: gewollt je Konfiguration, kein Vergessen.
    Deliberate := False;
    for Index := 0 to High(Tokens) do
      if (Tokens[Index].Kind = TPascalTokenKind.Directive) and TConditionalBranches.Exclusive(
        TConditionalBranches.PathAt(Paths, Index), TConditionalBranches.PathAt(Paths, Off.Token)) then
        for Item in SwitchesOf(Tokens[Index].Text) do
          if (Item.Switch = Off.Item.Switch) and not Item.Off then
            Deliberate := True;
    if Deliberate then
      Continue;
    Fixes := nil;
    Block := NextBlock(AContext.Tree, Tokens[Off.Token].Offset + Length(Tokens[Off.Token].Text));
    if Block <> nil then
    begin
      Line := Block.EndPos.Line;
      Indent := '';
      if Tokens[Off.Token].StartPos.Line <= High(Lines) then
        Indent := TTextLines.IndentOf(Lines[Tokens[Off.Token].StartPos.Line]);
      if Line <= High(Lines) then
        // Bereichs- und Überlaufprüfung: {$R+} schaltet sie womöglich erst ein, wenn das Projekt sie aus hat;
        // deshalb nur einzeln.
        Fixes := [TRuleFix.Create('Nach dem nächsten Block wiederherstellen',
          [TRuleEdit.Create(TTextRange.Create(Line, Length(Lines[Line]), Line, Length(Lines[Line])),
          LineBreak + Indent + RestoreText(Off.Item))], (Off.Item.Switch <> 'RANGECHECKS') and
          (Off.Item.Switch <> 'OVERFLOWCHECKS'))];
    end;
    AReport.Add(TTextRange.Create(Tokens[Off.Token].StartPos, Tokens[Off.Token].EndPos), SwitchMessage(Off.Item),
      TRuleConfidence.High, Fixes);
  end;
end;

procedure RegisterDirectiveRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TConditionalDirectiveUnbalancedRule.Create);
  ARegistry.Register(TDirectiveTypoRule.Create);
  ARegistry.Register(TCompilerWarningsDisabledRule.Create);
end;

end.
