unit Atlas.Common.Rules.Builtin.Directives;

// Regeln für Compiler-Direktiven (#909, Gruppe Compiler vorab):
//   conditional-directive-unbalanced  Bedingte Direktiven unvollständig oder
//                                     unbekannt (#989): {$IF…} ohne {$ENDIF}
//                                     (E2095, E2280), {$ELSE}/{$ENDIF} ohne
//                                     Gegenstück (E2279), fehlendes oder
//                                     ungültiges Symbol (E2173), unbekannte
//                                     Direktive oder {$WARN}-Bezeichner (W1030),
//                                     {$POPOPT}/{$PUSHOPT} ohne Gegenstück
//                                     (W1078, W1079), ungültiger Wert für
//                                     {$ALIGN} (E2573).
//
// Die Regel liest die Direktiven-Token des ganzen Textes, auch in inaktiven
// Zweigen; dort zählt Delphi die Verschachtelung ebenfalls. Unbekannte Namen
// prüft sie nicht in Zweigen, deren Bedingung FPC abfragt ({$IFDEF FPC}{$MODE
// DELPHI}{$ENDIF}). {$PUSHOPT}/{$POPOPT} prüft sie nur, wenn keines davon in
// einem bedingten Zweig steht.

interface

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  ConditionalDirectiveUnbalancedRuleId = 'conditional-directive-unbalanced';

type
  TConditionalDirectiveUnbalancedRule = class(TInterfacedObject, IRule)
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
  Atlas.Common.Pascal.DirectiveNames;

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
  LineBreak: string;

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
    Closest := TDirectiveNames.Closest(AName, TDirectiveNames.Directives);
    if (Closest <> '') and ReplaceFix(AIndex, AName, Closest, '{$' + Closest + '}', 1, Fix) then
      AReport.Add(RangeOf(AIndex), Format('Unbekannte Direktive {$%s}; gemeint ist wohl {$%s} (wie W1030).',
        [AName, Closest]), TRuleConfidence.High, [Fix])
    else
      AReport.Add(RangeOf(AIndex), Format('Unbekannte Direktive {$%s} (wie W1030).', [AName]), TRuleConfidence.High);
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
    Closest := TDirectiveNames.Closest(Id, TDirectiveNames.Warnings);
    if (Closest <> '') and ReplaceFix(AIndex, Id, Closest, Closest, AFrom, Fix) then
      AReport.Add(RangeOf(AIndex), Format('Unbekannte Warnung %s in {$WARN}; gemeint ist wohl %s (wie W1030).',
        [Id, Closest]), TRuleConfidence.High, [Fix])
    else
      AReport.Add(RangeOf(AIndex), Format('Unbekannte Warnung %s in {$WARN} (wie W1030).', [Id]),
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
  for Index := 0 to High(Tokens) do
    if Tokens[Index].Kind = TPascalTokenKind.Directive then
      Visit(Index);
  for Index := 0 to High(Stack) do
    Unclosed(Stack[Index], Index = High(Stack));
  CheckOptionStack;
end;

procedure RegisterDirectiveRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TConditionalDirectiveUnbalancedRule.Create);
end;

end.
