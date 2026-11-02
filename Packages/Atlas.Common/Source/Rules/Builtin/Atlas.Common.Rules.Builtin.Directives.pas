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
//   compiler-directive-invalid        Compileranweisungen, die dcc ablehnt oder
//                                     selbst meldet (#1379): {$MESSAGE WARN|HINT}
//                                     (W1054, H1054), {$WEAKPACKAGEUNIT ON} mit
//                                     {$DENYPACKAGEUNIT ON} (E2222),
//                                     {$DESIGNONLY}/{$RUNONLY} in einer Unit
//                                     (E2224), {$OBJTYPENAME} an einem Alias
//                                     (E2560), {$CODEPAGE} über 65535 (E1030),
//                                     fehlende Datei aus {$I} (F1026) bzw. {$R}
//                                     (E1026), Include-Datei, die sich über
//                                     unbedingte {$I} selbst einbindet (E2245).
//
// Die Regel liest die Direktiven-Token des ganzen Textes, auch in inaktiven
// Zweigen; dort zählt Delphi die Verschachtelung ebenfalls. Unbekannte Namen
// prüft sie nicht in Zweigen, deren Bedingung FPC abfragt ({$IFDEF FPC}{$MODE
// DELPHI}{$ENDIF}). {$PUSHOPT}/{$POPOPT} prüft sie nur, wenn keines davon in
// einem bedingten Zweig steht.
//
// compiler-directive-invalid prüft nur Direktiven außerhalb bedingter Zweige:
// Welcher Zweig gilt, weiß die Regel nicht, und dcc meldet nur aus geltenden.
// Dateien sucht sie neben der Unit (TRuleContext.FileExists) und über die
// Suchpfade des Projekts (IRuleUnitLookup.FindFile); ohne sichere Aussage
// schweigt sie. {$R Name.res Name.rc}, Formulare und Masken ({$R *.res}) prüft
// sie nicht, ebenso keine .res, neben der eine .rc gleichen Namens liegt (die
// IDE übersetzt sie vor dem Compiler). {$MESSAGE} ohne Art und mit ERROR/FATAL
// ist noch nicht mit dcc abgeglichen und bleibt still.
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
  CompilerDirectiveInvalidRuleId = 'compiler-directive-invalid';

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

  TCompilerDirectiveInvalidRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterDirectiveRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.ConditionalBranches,
  Atlas.Common.Pascal.DirectiveNames,
  Atlas.Common.Pascal.LanguageFeatures,
  Atlas.Common.Pascal.Lexer,
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
  begin
    if CharInSet(Ch, [' ', #9, #10, #13]) then
    begin
      Space := True;
    end
    else
    begin
      if Space then
      begin
        Result := Result + ' ';
      end;
      Space := False;
      Result := Result + Ch;
    end;
  end;
  if Length(Result) > AMax then
  begin
    Result := Copy(Result, 1, AMax - 1) + '…';
  end;
end;

/// <summary>Erstes Wort bis Leerraum oder Komma.</summary>
function FirstWord(const AText: string): string;
var
  Index: Integer;
begin
  Index := 1;
  while (Index <= Length(AText)) and not CharInSet(AText[Index], [' ', #9, #10, #13, ',']) do
  begin
    Inc(Index);
  end;
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
      begin
        Inc(Index);
      end;
      if StartsText('FPC', Copy(AText, Start, Index - Start)) then
      begin
        Exit(True);
      end;
    end
    else
    begin
      Inc(Index);
    end;
  end;
  Result := False;
end;

/// <summary>Ersatz in der Schreibweise des Originals: groß bleibt groß, sonst klein.</summary>
function LikeOriginal(const AOriginal, AReplacement: string): string;
begin
  if AOriginal = UpperCase(AOriginal) then
  begin
    Result := UpperCase(AReplacement);
  end
  else
  begin
    Result := LowerCase(AReplacement);
  end;
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
    begin
      Exit;
    end;
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
    begin
      Alone := Tokens[AIndex - 1].EndPos.Line < Line;
    end;
    if Alone and (AIndex < High(Tokens)) then
    begin
      Alone := Tokens[AIndex + 1].StartPos.Line > Line;
    end;
    if Alone then
    begin
      Result := TRuleFix.Create(ATitle, [TRuleEdit.Create(TTextRange.Create(Line, 0, Line + 1, 0), '')]);
    end
    else
    begin
      Result := TRuleFix.Create(ATitle, [TRuleEdit.Create(RangeOf(AIndex), '')]);
    end;
  end;

  /// <summary>{$ENDIF} vor der ersten Leerzeile hinter der Kette; False ohne Leerzeile.</summary>
  function EndifFix(const AOpen: TOpenConditional; out AFix: TRuleFix): Boolean;
  var
    Index, Line: Integer;
  begin
    AFix := Default(TRuleFix);
    for Index := AOpen.Last + 1 to High(Tokens) do
    begin
      if Tokens[Index].StartPos.Line > Tokens[Index - 1].EndPos.Line + 1 then
      begin
        Line := Tokens[Index - 1].EndPos.Line;
        AFix := TRuleFix.Create(Format('{$ENDIF} nach Zeile %d ergänzen', [Line + 1]),
          [TRuleEdit.Create(TTextRange.Create(Line + 1, 0, Line + 1, 0),
          StringOfChar(' ', Tokens[AOpen.Opening].StartPos.Character) + '{$ENDIF}' + LineBreak)]);
        Exit(True);
      end;
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
    begin
      AReport.Add(RangeOf(AIndex), Format('{$%s} ohne Symbol (wie E2173).', [AName]), TRuleConfidence.High);
    end
    else if not IsValidIdent(Symbol) then
    begin
      AReport.Add(RangeOf(AIndex), Format('%s ist kein gültiges Symbol für {$%s} (wie E2173).', [Symbol, AName]),
        TRuleConfidence.High);
    end;
  end;

  procedure CheckAlignValue(AIndex: Integer; const AValue: string; ALong: Boolean);
  begin
    if AValue = '' then
    begin
      Exit;
    end;
    if MatchText(AValue, ['1', '2', '4', '8', '16']) then
    begin
      Exit;
    end;
    if ALong and MatchText(AValue, ['ON', 'OFF']) then
    begin
      Exit;
    end;
    if not ALong and not CharInSet(AValue[1], ['0'..'9']) then
    begin
      Exit;
    end;
    AReport.Add(RangeOf(AIndex), Format('Ungültiger Wert %s für {$ALIGN}; erlaubt sind ON, OFF, 1, 2, 4, 8 und 16 ' +
      '(wie E2573).', [AValue]), TRuleConfidence.High);
  end;

  procedure CheckShortSwitches(AIndex: Integer; const ABody: string);
  var
    Part: string;
  begin
    for Part in SplitString(ABody, ',') do
    begin
      if SameText(TDirectiveNames.LeadingName(Trim(Part)), 'A') then
      begin
        CheckAlignValue(AIndex, Trim(Copy(Trim(Part), 2, MaxInt)), False);
      end;
    end;
  end;

  procedure CheckUnknown(AIndex: Integer; const AName: string);
  var
    Closest: string;
    Fix: TRuleFix;
  begin
    if InFpcBranch or TDirectiveNames.IsDirective(AName) then
    begin
      Exit;
    end;
    Closest := TTextFuzzy.Closest(AName, TDirectiveNames.Directives);
    if (Closest <> '') and ReplaceFix(AIndex, AName, Closest, '{$' + Closest + '}', 1, Fix) then
    begin
      AReport.Add(RangeOf(AIndex), Format('Unbekannte Direktive {$%s}; gemeint ist wohl {$%s} (wie %s).',
        [AName, Closest, mUnknownCode]), TRuleConfidence.High, [Fix]);
    end
    else
    begin
      AReport.Add(RangeOf(AIndex), Format('Unbekannte Direktive {$%s} (wie %s).', [AName, mUnknownCode]),
        TRuleConfidence.High);
    end;
  end;

  /// <summary>AFrom: erstes Zeichen hinter WARN in der Direktive.</summary>
  procedure CheckWarn(AIndex, AFrom: Integer; const ARest: string);
  var
    Id, Closest: string;
    Fix: TRuleFix;
  begin
    Id := TDirectiveNames.LeadingName(ARest);
    if (Id = '') or InFpcBranch or TDirectiveNames.IsWarning(Id) then
    begin
      Exit;
    end;
    Closest := TTextFuzzy.Closest(Id, TDirectiveNames.Warnings);
    if (Closest <> '') and ReplaceFix(AIndex, Id, Closest, Closest, AFrom, Fix) then
    begin
      AReport.Add(RangeOf(AIndex), Format('Unbekannte Warnung %s in {$WARN}; gemeint ist wohl %s (wie %s).',
        [Id, Closest, mUnknownCode]), TRuleConfidence.High, [Fix]);
    end
    else
    begin
      AReport.Add(RangeOf(AIndex), Format('Unbekannte Warnung %s in {$WARN} (wie %s).', [Id, mUnknownCode]),
        TRuleConfidence.High);
    end;
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
    begin
      Item.Condition := 'not ' + FirstWord(ARest);
    end
    else if AName = 'IFDEF' then
    begin
      Item.Condition := FirstWord(ARest);
    end
    else
    begin
      Item.Condition := Compact(ARest, 40);
    end;
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
    begin
      Code := 'E2280';
    end;
    Message := Format('%s wird nie geschlossen; der Rest der Datei hängt an %s (wie %s).',
      [Compact(Tokens[AItem.Opening].Text, 60), AItem.Condition, Code]);
    if ATop and EndifFix(AItem, Fix) then
    begin
      AReport.Add(RangeOf(AItem.Opening), Message, TRuleConfidence.High, [Fix]);
    end
    else
    begin
      AReport.Add(RangeOf(AItem.Opening), Message, TRuleConfidence.High);
    end;
  end;

  procedure Visit(AIndex: Integer);
  var
    Body, Name, Rest: string;
  begin
    Body := TDirectiveNames.Body(Tokens[AIndex].Text);
    Name := UpperCase(TDirectiveNames.LeadingName(Body));
    Rest := Trim(Copy(Body, Length(Name) + 1, MaxInt));
    if Name = '' then
    begin
      Exit;
    end;
    if (Name = 'IF') or (Name = 'IFDEF') or (Name = 'IFNDEF') or (Name = 'IFOPT') then
    begin
      if (Name = 'IFDEF') or (Name = 'IFNDEF') then
      begin
        CheckSymbol(AIndex, Name, Rest);
      end;
      Open(AIndex, Name, Rest);
    end
    else if (Name = 'ELSE') or (Name = 'ELSEIF') then
    begin
      if Stack = nil then
      begin
        Stray(AIndex, Name);
      end
      else if Stack[High(Stack)].HadElse then
      begin
        AReport.Add(RangeOf(AIndex), Format('{$%s} nach {$ELSE} von %s aus Zeile %d (wie E2279).',
          [Name, Compact(Tokens[Stack[High(Stack)].Opening].Text, 60),
          Tokens[Stack[High(Stack)].Opening].StartPos.Line + 1]), TRuleConfidence.High);
      end
      else
      begin
        Stack[High(Stack)].HadElse := Name = 'ELSE';
        Stack[High(Stack)].Last := AIndex;
        if MentionsFpc(Rest) then
        begin
          Stack[High(Stack)].Fpc := True;
        end;
      end;
    end
    else if (Name = 'ENDIF') or (Name = 'IFEND') then
    begin
      if Stack = nil then
      begin
        Stray(AIndex, Name);
      end
      else
      begin
        SetLength(Stack, Length(Stack) - 1);
      end;
    end
    else if (Name = 'DEFINE') or (Name = 'UNDEF') then
    begin
      CheckSymbol(AIndex, Name, Rest);
    end
    else if (Name = 'PUSHOPT') or (Name = 'POPOPT') then
    begin
      Options := Options + [AIndex];
      OptionInBranch := OptionInBranch or (Stack <> nil);
    end
    else if Name = 'ALIGN' then
    begin
      CheckAlignValue(AIndex, FirstWord(Rest), True);
    end
    else if Name = 'WARN' then
    begin
      CheckWarn(AIndex, Pos(TDirectiveNames.LeadingName(Body), Tokens[AIndex].Text) + Length(Name), Rest);
    end
    else if Length(Name) = 1 then
    begin
      CheckShortSwitches(AIndex, Body);
    end
    else
    begin
      CheckUnknown(AIndex, TDirectiveNames.LeadingName(Body));
    end;
  end;

  procedure CheckOptionStack;
  var
    Pushes: TArray<Integer>;
    Index: Integer;
  begin
    if OptionInBranch then
    begin
      Exit;
    end;
    Pushes := nil;
    for Index in Options do
    begin
      if SameText(TDirectiveNames.LeadingName(TDirectiveNames.Body(Tokens[Index].Text)), 'PUSHOPT') then
      begin
        Pushes := Pushes + [Index];
      end
      else if Pushes = nil then
      begin
        AReport.Add(RangeOf(Index), '{$POPOPT} ohne vorheriges {$PUSHOPT} (wie W1078).', TRuleConfidence.High);
      end
      else
      begin
        SetLength(Pushes, Length(Pushes) - 1);
      end;
    end;
    for Index in Pushes do
    begin
      AReport.Add(RangeOf(Index), '{$PUSHOPT} ohne passendes {$POPOPT} (wie W1079).', TRuleConfidence.High);
    end;
  end;

var
  Index: Integer;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
  LineBreak := #10;
  if Pos(#13#10, AContext.Text) > 0 then
  begin
    LineBreak := #13#10;
  end;
  Stack := nil;
  Options := nil;
  OptionInBranch := False;
  // Delphi 13 meldet unbekannte Direktiven und {$WARN}-Bezeichner als Fehler E1030, ältere Versionen als W1030
  // (#1382).
  mUnknownCode := 'W1030';
  if TLanguageFeatures.IsAtLeast(AContext.DelphiVersion, Delphi13) then
  begin
    mUnknownCode := 'E1030';
  end;
  for Index := 0 to High(Tokens) do
  begin
    if Tokens[Index].Kind = TPascalTokenKind.Directive then
    begin
      Visit(Index);
    end;
  end;
  for Index := 0 to High(Stack) do
  begin
    Unclosed(Stack[Index], Index = High(Stack));
  end;
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
      begin
        Result := Result + [Token.Offset];
      end;
      Continue;
    end;
    Body := TDirectiveNames.Body(Token.Text);
    Name := UpperCase(TDirectiveNames.LeadingName(Body));
    Rest := Copy(Body, Length(Name) + 1, MaxInt);
    if (Name = 'IF') or (Name = 'IFDEF') or (Name = 'IFNDEF') or (Name = 'IFOPT') then
    begin
      Stack := Stack + [Fpc or MentionsFpc(Rest)];
    end
    else if (Name = 'ELSEIF') and (Stack <> nil) then
    begin
      Stack[High(Stack)] := Stack[High(Stack)] or MentionsFpc(Rest);
    end
    else if ((Name = 'ENDIF') or (Name = 'IFEND')) and (Stack <> nil) then
    begin
      SetLength(Stack, Length(Stack) - 1);
    end;
  end;
end;

procedure TDirectiveTypoRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Fpc: TArray<Integer>;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  Fpc := nil;
  if Pos('{$', AContext.Text) > 0 then
  begin
    Fpc := FpcOffsets(AContext.Tree.Tokens);
  end;
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
      begin
        Exit;
      end;
      // Nach einer Property steht nur default, nach Routinenköpfen eine der Direktiven.
      if ANode.Parent.Kind = TSyntaxKind.PropertyDecl then
      begin
        Candidates := ['default'];
      end
      // Methodenzuordnung "function IFoo.GetX = MyGetX;": "= MyGetX" ist keine Direktive (#1325).
      else if (ANode.Parent.Kind = TSyntaxKind.RoutineHeader) and ANode.Parent.IsMethodResolution then
      begin
        Exit;
      end
      else if ANode.Parent.Kind = TSyntaxKind.RoutineHeader then
      begin
        Candidates := TDirectiveNames.RoutineDirectives;
      end
      else
      begin
        Exit;
      end;
      if MatchText(ANode.Name, Candidates) then
      begin
        Exit;
      end;
      for Offset in Fpc do
      begin
        if Offset = ANode.StartOffset then
        begin
          Exit;
        end;
      end;
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
      begin
        AReport.Add(Range, Format('Unbekannte Direktive %s (wie E2070).', [Word]), TRuleConfidence.High);
      end;
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
    begin
      Exit;
    end;
    Item.Switch := Name;
    Item.Off := Rest = 'OFF';
    Result := [Item];
    Exit;
  end;
  if Name = 'WARN' then
  begin
    Words := Rest.Split([' ', #9], TStringSplitOptions.ExcludeEmpty);
    if (Length(Words) <> 2) or not MatchStr(Words[1], ['ON', 'OFF', 'ERROR', 'DEFAULT']) then
    begin
      Exit;
    end;
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
  begin
    if (Length(Trim(Part)) <> 2) or not CharInSet(Trim(Part)[1], ['A'..'Z', 'a'..'z']) or
      not CharInSet(Trim(Part)[2], ['+', '-']) then
    begin
      Exit;
    end;
  end;
  for Part in Parts do
  begin
    Item := Default(TCompilerSwitch);
    Item.Written := UpperCase(Trim(Part)[1]);
    if Item.Written = 'R' then
    begin
      Item.Switch := 'RANGECHECKS';
    end
    else if Item.Written = 'Q' then
    begin
      Item.Switch := 'OVERFLOWCHECKS';
    end
    else
    begin
      Continue;
    end;
    Item.Off := Trim(Part)[2] = '-';
    Result := Result + [Item];
  end;
end;

/// <summary>Direktive, die AItem wieder einschaltet.</summary>
function RestoreText(const AItem: TCompilerSwitch): string;
begin
  if StartsStr('WARN:', AItem.Switch) then
  begin
    Result := Format('{$WARN %s DEFAULT}', [Copy(AItem.Switch, 6, MaxInt)]);
  end
  else if Length(AItem.Written) = 1 then
  begin
    Result := Format('{$%s+}', [AItem.Written]);
  end
  else
  begin
    Result := Format('{$%s ON}', [AItem.Written]);
  end;
end;

function SwitchMessage(const AItem: TCompilerSwitch): string;
begin
  if AItem.Switch = 'WARNINGS' then
  begin
    Result := 'WARNINGS bleibt bis zum Ende der Unit aus; alle späteren Warnungen fehlen.';
  end
  else if AItem.Switch = 'HINTS' then
  begin
    Result := 'HINTS bleibt bis zum Ende der Unit aus; alle späteren Hinweise fehlen.';
  end
  else if AItem.Switch = 'RANGECHECKS' then
  begin
    Result := 'Die Bereichsprüfung bleibt bis zum Ende der Unit aus; Überschreitungen fallen nicht mehr auf.';
  end
  else if AItem.Switch = 'OVERFLOWCHECKS' then
  begin
    Result := 'Die Überlaufprüfung bleibt bis zum Ende der Unit aus; Überläufe fallen nicht mehr auf.';
  end
  else
  begin
    Result := Format('Die Warnung %s bleibt bis zum Ende der Unit aus.', [Copy(AItem.Switch, 6, MaxInt)]);
  end;
end;

/// <summary>Steht AItem in der Liste allow (Warnungsname, WARNINGS, HINTS, R bzw. RANGECHECKS, Q bzw.
/// OVERFLOWCHECKS)?</summary>
function SwitchAllowed(const AItem: TCompilerSwitch; const AAllow: TArray<string>): Boolean;
begin
  if StartsStr('WARN:', AItem.Switch) then
  begin
    Result := MatchText(Copy(AItem.Switch, 6, MaxInt), AAllow);
  end
  else
  begin
    Result := MatchText(AItem.Switch, AAllow) or ((AItem.Switch = 'RANGECHECKS') and MatchText('R', AAllow)) or
      ((AItem.Switch = 'OVERFLOWCHECKS') and MatchText('Q', AAllow));
  end;
end;

/// <summary>Folgt hinter dem Token AIndex noch Code außer dem abschließenden "end."?</summary>
function CodeFollows(const ATokens: TArray<TPascalToken>; AIndex: Integer): Boolean;
var
  Index: Integer;
begin
  Result := False;
  for Index := AIndex + 1 to High(ATokens) do
  begin
    if not (ATokens[Index].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) and
      not ATokens[Index].IsKeyword('end') and not ATokens[Index].IsSymbol('.') then
    begin
      Exit(True);
    end;
  end;
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
    begin
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
    end;
    Node := Inner;
  end;
  if (Result <> nil) and (Result.Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection,
    TSyntaxKind.InitializationSection, TSyntaxKind.FinalizationSection]) then
  begin
    Result := nil;
  end;
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
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
  Offs := nil;
  for Index := 0 to High(Tokens) do
  begin
    if Tokens[Index].Kind = TPascalTokenKind.Directive then
    begin
      for Item in SwitchesOf(Tokens[Index].Text) do
      begin
        if Item.Switch = 'POPOPT' then
        begin
          // {$POPOPT} stellt alles wieder her, was seit {$PUSHOPT} umgestellt wurde.
          for Other := 0 to High(Offs) do
          begin
            Offs[Other].Restored := True;
          end;
        end
        else if Item.Off then
        begin
          Off := Default(TSwitchOff);
          Off.Item := Item;
          Off.Token := Index;
          Offs := Offs + [Off];
        end
        else
        begin
          for Other := 0 to High(Offs) do
          begin
            if Offs[Other].Item.Switch = Item.Switch then
            begin
              Offs[Other].Restored := True;
            end;
          end;
        end;
      end;
    end;
  end;
  if Offs = nil then
  begin
    Exit;
  end;
  Allow := TRuleOptions.Strings(AContext.Options, 'allow', nil);
  Paths := TConditionalBranches.Paths(Tokens);
  Lines := TTextLines.SplitLines(AContext.Text, LineBreak);
  for Off in Offs do
  begin
    if Off.Restored or SwitchAllowed(Off.Item, Allow) or not CodeFollows(Tokens, Off.Token) then
    begin
      Continue;
    end;
    // {$IFDEF DEBUG}{$R+}{$ELSE}{$R-}{$ENDIF}: gewollt je Konfiguration, kein Vergessen.
    Deliberate := False;
    for Index := 0 to High(Tokens) do
    begin
      if (Tokens[Index].Kind = TPascalTokenKind.Directive) and TConditionalBranches.Exclusive(
        TConditionalBranches.PathAt(Paths, Index), TConditionalBranches.PathAt(Paths, Off.Token)) then
      begin
        for Item in SwitchesOf(Tokens[Index].Text) do
        begin
          if (Item.Switch = Off.Item.Switch) and not Item.Off then
          begin
            Deliberate := True;
          end;
        end;
      end;
    end;
    if Deliberate then
    begin
      Continue;
    end;
    Fixes := nil;
    Block := NextBlock(AContext.Tree, Tokens[Off.Token].Offset + Length(Tokens[Off.Token].Text));
    if Block <> nil then
    begin
      Line := Block.EndPos.Line;
      Indent := '';
      if Tokens[Off.Token].StartPos.Line <= High(Lines) then
      begin
        Indent := TTextLines.IndentOf(Lines[Tokens[Off.Token].StartPos.Line]);
      end;
      if Line <= High(Lines) then
      begin
        // Bereichs- und Überlaufprüfung: {$R+} schaltet sie womöglich erst ein, wenn das Projekt sie aus hat;
        // deshalb nur einzeln.
        Fixes := [TRuleFix.Create('Nach dem nächsten Block wiederherstellen',
          [TRuleEdit.Create(TTextRange.Create(Line, Length(Lines[Line]), Line, Length(Lines[Line])),
          LineBreak + Indent + RestoreText(Off.Item))], (Off.Item.Switch <> 'RANGECHECKS') and
          (Off.Item.Switch <> 'OVERFLOWCHECKS'))];
      end;
    end;
    AReport.Add(TTextRange.Create(Tokens[Off.Token].StartPos, Tokens[Off.Token].EndPos), SwitchMessage(Off.Item),
      TRuleConfidence.High, Fixes);
  end;
end;

{ TCompilerDirectiveInvalidRule }

const
  /// <summary>So tief folgt compiler-directive-invalid Include-Dateien in Include-Dateien.</summary>
  cMaxIncludeDepth = 16;
  /// <summary>Zeichen, die in keinem Dateinamen stehen (Masken, Makros); dann schweigt die Regel.</summary>
  cNoFileChars: TSysCharSet = ['*', '?', '<', '>', '|', '"', '%'];

/// <summary>Erstes Argument einer Direktive: Text in Hochkommas ('' für ein Hochkomma) oder bis zum Leerraum;
/// ARest erhält den Rest ohne Rand.</summary>
function FirstArgument(const AText: string; out ARest: string): string;
var
  mText: string;
  mIndex: Integer;
begin
  Result := '';
  mText := Trim(AText);
  mIndex := 1;
  if (mText <> '') and (mText[1] = '''') then
  begin
    mIndex := 2;
    while mIndex <= Length(mText) do
    begin
      if mText[mIndex] = '''' then
      begin
        if (mIndex < Length(mText)) and (mText[mIndex + 1] = '''') then
        begin
          Inc(mIndex);
        end
        else
        begin
          Break;
        end;
      end;
      Result := Result + mText[mIndex];
      Inc(mIndex);
    end;
  end
  else
  begin
    while (mIndex <= Length(mText)) and not CharInSet(mText[mIndex], [' ', #9, #10, #13]) do
    begin
      Inc(mIndex);
    end;
    Result := Copy(mText, 1, mIndex - 1);
  end;
  ARest := Trim(Copy(mText, mIndex + 1, MaxInt));
end;

/// <summary>Kann AName ein Dateiname sein (keine Maske, kein Makro)?</summary>
function PlainFileName(const AName: string): Boolean;
var
  mChar: Char;
begin
  Result := AName <> '';
  for mChar in AName do
  begin
    if CharInSet(mChar, cNoFileChars) then
    begin
      Exit(False);
    end;
  end;
end;

/// <summary>Namen, unter denen dcc die Datei aus {$I} bzw. {$R} sucht: wie geschrieben, ohne passende Endung
/// zusätzlich mit .inc und .pas bzw. .res. Lieber ein Name zu viel als eine Meldung, wo dcc die Datei findet.
/// </summary>
function FileCandidates(const AName: string; AResource: Boolean): TArray<string>;
begin
  Result := [AName];
  if AResource then
  begin
    if not EndsText('.res', AName) then
    begin
      Result := Result + [AName + '.res'];
    end;
  end
  else if not EndsText('.inc', AName) and not EndsText('.pas', AName) then
  begin
    Result := Result + [AName + '.inc', AName + '.pas'];
  end;
end;

/// <summary>Datei aus {$I}/{$INCLUDE} bzw. {$R}/{$RESOURCE} (ARest: alles hinter dem Namen der Direktive);
/// False für Kurzschalter ({$I+}, {$R-,Q+}) und ohne Dateinamen.</summary>
function DirectiveFile(const AName, ARest: string; out AResource: Boolean; out AFile, AMore: string): Boolean;
begin
  AFile := '';
  AMore := '';
  AResource := (AName = 'R') or (AName = 'RESOURCE');
  Result := AResource or (AName = 'I') or (AName = 'INCLUDE');
  if not Result then
  begin
    Exit;
  end;
  Result := (ARest <> '') and not CharInSet(ARest[1], ['+', '-', ',']);
  if Result then
  begin
    AFile := FirstArgument(ARest, AMore);
  end;
end;

/// <summary>Schlüssel einer Include-Datei für den Vergleich: "\" als Trenner, klein.</summary>
function IncludeKey(const AName: string): string;
begin
  Result := LowerCase(StringReplace(AName, '/', '\', [rfReplaceAll]));
end;

function TCompilerDirectiveInvalidRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(CompilerDirectiveInvalidRuleId, TRuleSeverity.Error,
    'Compileranweisung ungültig oder Datei aus {$I}/{$R} fehlt');
end;

procedure TCompilerDirectiveInvalidRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TArray<TPascalToken>;
  mPaths: TArray<string>;
  mWeak, mDeny, mPackageUnknown: Boolean;
  mIndex: Integer;

  function RangeOf(AIndex: Integer): TTextRange;
  begin
    Result := TTextRange.Create(mTokens[AIndex].StartPos, mTokens[AIndex].EndPos);
  end;

  /// <summary>Gibt es eine der Dateien ACandidates (relativ zur Unit bzw. über die Suchpfade des Projekts)?
  /// Unknown ohne Dateizugriff oder wenn die Suche keine sichere Aussage trifft.</summary>
  function Locate(const ACandidates: TArray<string>): TRuleUnitAnswer;
  var
    mName: string;
    mAnswer: TRuleUnitAnswer;
  begin
    if not Assigned(AContext.FileExists) or (AContext.FileName = '') then
    begin
      Exit(TRuleUnitAnswer.Unknown);
    end;
    for mName in ACandidates do
    begin
      if AContext.FileExists(mName) then
      begin
        Exit(TRuleUnitAnswer.Found);
      end;
    end;
    if AContext.Units = nil then
    begin
      Exit(TRuleUnitAnswer.Unknown);
    end;
    Result := TRuleUnitAnswer.Missing;
    for mName in ACandidates do
    begin
      mAnswer := AContext.Units.FindFile(mName, AContext.FileName);
      if mAnswer = TRuleUnitAnswer.Found then
      begin
        Exit(TRuleUnitAnswer.Found);
      end;
      if mAnswer = TRuleUnitAnswer.Unknown then
      begin
        Result := TRuleUnitAnswer.Unknown;
      end;
    end;
  end;

  /// <summary>Text der Include-Datei AName relativ zum Ordner der Unit; AFound ist der gelesene Name.</summary>
  function ReadInclude(const AName: string; out AFound, AText: string): Boolean;
  var
    mName: string;
    mData: TBytes;
    mFormat: TFileFormat;
  begin
    AFound := '';
    AText := '';
    Result := False;
    if not Assigned(AContext.ReadFile) or not PlainFileName(AName) then
    begin
      Exit;
    end;
    for mName in FileCandidates(AName, False) do
    begin
      if AContext.ReadFile(mName, mData) then
      begin
        AFound := mName;
        AText := TFileEncoding.Decode(mData, mFormat);
        Exit(True);
      end;
    end;
  end;

  /// <summary>Bindet sich die Include-Datei AName (relativ zur Unit) über unbedingte {$I} selbst ein, direkt oder
  /// über weitere Include-Dateien? AStack: Schlüssel der Dateien auf dem Weg dorthin; AChain: der Weg bis zur
  /// Wiederholung, z. B. "A.inc → B.inc → A.inc".</summary>
  function Recursive(const AName: string; const AStack: TArray<string>; out AChain: string): Boolean;
  var
    mFound, mText, mKey, mBody, mDirective, mRest, mFile, mMore, mInner, mFolder: string;
    mResource: Boolean;
    mToken: TPascalToken;
    mDepth: Integer;
  begin
    AChain := '';
    Result := False;
    if (Length(AStack) >= cMaxIncludeDepth) or not ReadInclude(AName, mFound, mText) then
    begin
      Exit;
    end;
    mKey := IncludeKey(mFound);
    if IndexStr(mKey, AStack) >= 0 then
    begin
      AChain := ExtractFileName(mFound);
      Exit(True);
    end;
    mFolder := ExtractFilePath(StringReplace(mFound, '/', '\', [rfReplaceAll]));
    mDepth := 0;
    for mToken in TPascalLexer.Tokenize(mText) do
    begin
      if mToken.Kind <> TPascalTokenKind.Directive then
      begin
        Continue;
      end;
      mBody := TDirectiveNames.Body(mToken.Text);
      mDirective := UpperCase(TDirectiveNames.LeadingName(mBody));
      mRest := Trim(Copy(mBody, Length(mDirective) + 1, MaxInt));
      if MatchStr(mDirective, ['IF', 'IFDEF', 'IFNDEF', 'IFOPT']) then
      begin
        Inc(mDepth);
      end
      else if MatchStr(mDirective, ['ENDIF', 'IFEND']) then
      begin
        Dec(mDepth);
      end
      // Nur unbedingte {$I}: Ein Wächter wie {$IFNDEF X_INC}{$DEFINE X_INC} … {$ENDIF} beendet den Kreis.
      else if (mDepth = 0) and DirectiveFile(mDirective, mRest, mResource, mFile, mMore) and not mResource and
        PlainFileName(mFile) then
      begin
        if ExtractFileDrive(mFile) = '' then
        begin
          mFile := mFolder + mFile;
        end;
        if Recursive(mFile, AStack + [mKey], mInner) then
        begin
          AChain := ExtractFileName(mFound) + ' → ' + mInner;
          Exit(True);
        end;
      end;
    end;
  end;

  procedure CheckFile(AIndex: Integer; AResource: Boolean; const AFile, AMore: string);
  var
    mChain: string;
  begin
    if not PlainFileName(AFile) then
    begin
      Exit;
    end;
    if AResource then
    begin
      // {$R Name.res Name.rc}: Die .res entsteht beim Bau aus der .rc; Formulare prüft form-resource-missing.
      if (AMore <> '') or MatchText(ExtractFileExt(AFile), ['.dfm', '.fmx', '.xfm', '.lfm']) then
      begin
        Exit;
      end;
      // Eine .rc gleichen Namens übersetzt die IDE vor dem Compiler (RcCompile in der .dproj).
      if Assigned(AContext.FileExists) and AContext.FileExists(ChangeFileExt(AFile, '.rc')) then
      begin
        Exit;
      end;
      if Locate(FileCandidates(AFile, True)) = TRuleUnitAnswer.Missing then
      begin
        AReport.Add(RangeOf(AIndex), Format('Ressourcendatei %s nicht gefunden (wie E1026).', [AFile]));
      end;
      Exit;
    end;
    case Locate(FileCandidates(AFile, False)) of
      TRuleUnitAnswer.Missing:
        AReport.Add(RangeOf(AIndex), Format('Include-Datei %s nicht gefunden (wie F1026).', [AFile]));
      TRuleUnitAnswer.Found:
        if Recursive(AFile, nil, mChain) then
        begin
          AReport.Add(RangeOf(AIndex), Format('Rekursive Include-Datei: %s (wie E2245).', [mChain]));
        end;
    end;
  end;

  procedure CheckMessage(AIndex: Integer; const ARest: string);
  var
    mKind, mText, mAfter: string;
  begin
    // {$MESSAGE HINT|WARN 'Text'}; ohne Art und mit ERROR/FATAL noch nicht mit dcc abgeglichen.
    mKind := UpperCase(FirstArgument(ARest, mText));
    if (mText = '') or (mText[1] <> '''') then
    begin
      Exit;
    end;
    mText := FirstArgument(mText, mAfter);
    if mKind = 'WARN' then
    begin
      AReport.AddWithSeverity(RangeOf(AIndex), Format('{$MESSAGE WARN}: %s (wie W1054).', [mText]),
        TRuleSeverity.Warning, nil);
    end
    else if mKind = 'HINT' then
    begin
      AReport.AddWithSeverity(RangeOf(AIndex), Format('{$MESSAGE HINT}: %s (wie H1054).', [mText]),
        TRuleSeverity.Hint, nil);
    end;
  end;

  procedure CheckPackageSwitch(AIndex: Integer; const AName, ARest: string);
  var
    mValue, mAfter: string;
    mOn: Boolean;
  begin
    mValue := UpperCase(FirstArgument(ARest, mAfter));
    if (mValue <> 'ON') and (mValue <> 'OFF') then
    begin
      mPackageUnknown := True;
      Exit;
    end;
    mOn := mValue = 'ON';
    if AName = 'WEAKPACKAGEUNIT' then
    begin
      if mOn and mDeny and not mWeak and not mPackageUnknown then
      begin
        AReport.Add(RangeOf(AIndex), '{$WEAKPACKAGEUNIT ON} und {$DENYPACKAGEUNIT ON} schließen sich aus ' +
          '(wie E2222).');
      end;
      mWeak := mOn;
    end
    else
    begin
      if mOn and mWeak and not mDeny and not mPackageUnknown then
      begin
        AReport.Add(RangeOf(AIndex), '{$WEAKPACKAGEUNIT ON} und {$DENYPACKAGEUNIT ON} schließen sich aus ' +
          '(wie E2222).');
      end;
      mDeny := mOn;
    end;
  end;

  procedure CheckPackageOnly(AIndex: Integer; const AName, ARest: string);
  var
    mValue, mAfter: string;
  begin
    if (AContext.Tree.Root = nil) or (AContext.Tree.Root.Kind <> TSyntaxKind.UnitFile) then
    begin
      Exit;
    end;
    mValue := UpperCase(FirstArgument(ARest, mAfter));
    if (mValue = '') or (mValue = 'ON') then
    begin
      AReport.Add(RangeOf(AIndex), Format('{$%s} ist nur in einem Package (.dpk) erlaubt, nicht in einer Unit ' +
        '(wie E2224).', [AName]));
    end;
  end;

  /// <summary>Ist ADecl ein globaler, schlichter Alias wie TZahl = Integer (nicht TZahl = type Integer)?</summary>
  function IsGlobalAlias(ADecl: TSyntaxNode): Boolean;
  var
    mTarget: TSyntaxNode;
    mToken: Integer;
  begin
    Result := False;
    if (ADecl.Parent = nil) or (ADecl.Parent.Kind <> TSyntaxKind.TypeSection) or (ADecl.Parent.Parent = nil) or
      not (ADecl.Parent.Parent.Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection]) or
      (ADecl.ChildCount <> 1) then
    begin
      Exit;
    end;
    mTarget := ADecl[0];
    if (mTarget.Kind <> TSyntaxKind.TypeReference) or (mTarget.ChildCount > 0) or
      MatchText(mTarget.Name, ['', 'string', 'file', 'const']) then
    begin
      Exit;
    end;
    mToken := AContext.Tree.FirstTokenFrom(mTarget.StartOffset) - 1;
    while (mToken >= 0) and (mTokens[mToken].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
    begin
      Dec(mToken);
    end;
    Result := (mToken >= 0) and (mTokens[mToken].Text = '=');
  end;

  procedure CheckObjTypeName(AIndex: Integer; const ARest: string);
  var
    mName, mAfter: string;
    mDecls, mPending: TArray<TSyntaxNode>;
    mDecl, mNode: TSyntaxNode;
    mChild: Integer;
  begin
    mName := FirstArgument(ARest, mAfter);
    if not IsValidIdent(mName) then
    begin
      Exit;
    end;
    // Iterativ (Bericht M1); Typen stehen nicht in Anweisungen.
    mDecls := nil;
    mPending := [AContext.Tree.Root];
    while mPending <> nil do
    begin
      mNode := mPending[High(mPending)];
      SetLength(mPending, Length(mPending) - 1);
      if (mNode.Kind = TSyntaxKind.TypeDecl) and SameText(mNode.Name, mName) then
      begin
        mDecls := mDecls + [mNode];
      end;
      if not (mNode.Kind in [TSyntaxKind.Block, TSyntaxKind.AsmBlock]) then
      begin
        for mChild := 0 to mNode.ChildCount - 1 do
        begin
          mPending := mPending + [mNode[mChild]];
        end;
      end;
    end;
    if mDecls = nil then
    begin
      Exit;
    end;
    for mDecl in mDecls do
    begin
      if not IsGlobalAlias(mDecl) then
      begin
        Exit;
      end;
    end;
    AReport.Add(RangeOf(AIndex), Format('{$OBJTYPENAME} gilt nicht für den Alias %s; erlaubt sind nur globale ' +
      'Typen, die kein Alias sind (wie E2560).', [mName]));
  end;

  procedure CheckCodePage(AIndex: Integer; const ARest: string);
  var
    mValue, mAfter: string;
    mNumber: Int64;
  begin
    // Codepages sind 16 Bit groß; welche installiert sind, weiß nur der Rechner, der übersetzt (E2424).
    mValue := FirstArgument(ARest, mAfter);
    if TryStrToInt64(mValue, mNumber) and (mNumber > 65535) then
    begin
      AReport.Add(RangeOf(AIndex), Format('%s ist keine Codepage für {$CODEPAGE} (wie E1030).', [mValue]));
    end;
  end;

  procedure Visit(AIndex: Integer);
  var
    mBody, mName, mRest, mFile, mMore: string;
    mResource: Boolean;
  begin
    mBody := TDirectiveNames.Body(mTokens[AIndex].Text);
    mName := UpperCase(TDirectiveNames.LeadingName(mBody));
    mRest := Trim(Copy(mBody, Length(mName) + 1, MaxInt));
    if (mName = 'WEAKPACKAGEUNIT') or (mName = 'DENYPACKAGEUNIT') then
    begin
      // Was in bedingten Zweigen steht, wird vielleicht nicht übersetzt: dann ohne Aussage.
      if TConditionalBranches.PathAt(mPaths, AIndex) <> '' then
      begin
        mPackageUnknown := True;
      end
      else
      begin
        CheckPackageSwitch(AIndex, mName, mRest);
      end;
      Exit;
    end;
    if TConditionalBranches.PathAt(mPaths, AIndex) <> '' then
    begin
      Exit;
    end;
    if DirectiveFile(mName, mRest, mResource, mFile, mMore) then
    begin
      CheckFile(AIndex, mResource, mFile, mMore);
    end
    else if mName = 'MESSAGE' then
    begin
      CheckMessage(AIndex, mRest);
    end
    else if (mName = 'DESIGNONLY') or (mName = 'RUNONLY') then
    begin
      CheckPackageOnly(AIndex, mName, mRest);
    end
    else if mName = 'OBJTYPENAME' then
    begin
      CheckObjTypeName(AIndex, mRest);
    end
    else if mName = 'CODEPAGE' then
    begin
      CheckCodePage(AIndex, mRest);
    end;
  end;

begin
  if (AContext.Tree = nil) or (Pos('$', AContext.Text) = 0) then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  mPaths := TConditionalBranches.Paths(mTokens);
  mWeak := False;
  mDeny := False;
  mPackageUnknown := False;
  for mIndex := 0 to High(mTokens) do
  begin
    if mTokens[mIndex].Kind = TPascalTokenKind.Directive then
    begin
      Visit(mIndex);
    end;
  end;
end;

procedure RegisterDirectiveRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TConditionalDirectiveUnbalancedRule.Create);
  ARegistry.Register(TDirectiveTypoRule.Create);
  ARegistry.Register(TCompilerWarningsDisabledRule.Create);
  ARegistry.Register(TCompilerDirectiveInvalidRule.Create);
end;

end.
