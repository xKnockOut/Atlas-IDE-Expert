unit Atlas.Common.Editing.DocumentationCommands;

// Schnellbefehle für Dokumentation und Markierungen (#306) im Rahmen aus #293:
//   /header           Dateikopf aus slashCommands.headerTemplate setzen bzw. das Jahr
//                     im vorhandenen Kopf fortschreiben
//   /deprecated Grund deprecated 'Grund' an die Deklaration darunter (bei Methoden
//                     an die in der Klasse) und <remarks>Veraltet: Grund</remarks>
//   /region-all       Methoden der Klasse in der implementation nach Gruppen in
//                     {$REGION}-Blöcke ordnen
// /bookmark entfällt laut Ergänzung vom 09.10.: Die IDE und Atlas haben eigene Lesezeichen. Vorhandene
// Kommentare "// @bookmark Name" findet die Symbolsuche weiter (Editing.Bookmarks).

interface

uses
  Atlas.Common.Editing.SlashCommands;

const
  /// <summary>Vorlage, wenn weder slashCommands.headerTemplate noch die Regel file-header eine vorgibt.</summary>
  DefaultHeaderTemplate = '{ {unit}' + #13#10 + '  Copyright (c) {jahr} {autor} }';

/// <summary>Trägt /header, /deprecated und /region-all in ARegistry ein.</summary>
procedure RegisterDocumentationCommands(ARegistry: TSlashCommandRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Editing.CommandSource;

type
  TTokens = TArray<TPascalToken>;

const
  RoutineKeywords: array[0..5] of string = ('procedure', 'function', 'constructor', 'destructor', 'operator',
    'class');
  Directives: array[0..29] of string = ('abstract', 'assembler', 'cdecl', 'deprecated', 'dispid', 'dynamic',
    'experimental', 'export', 'external', 'far', 'final', 'forward', 'inline', 'library', 'local', 'message',
    'near', 'overload', 'override', 'pascal', 'platform', 'register', 'reintroduce', 'safecall', 'static',
    'stdcall', 'unsafe', 'varargs', 'virtual', 'winapi');

function IsCode(const AToken: TPascalToken): Boolean;
begin
  Result := not (AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]);
end;

function NextCode(const ATokens: TTokens; AIndex: Integer): Integer;
begin
  Result := AIndex + 1;
  while (Result <= High(ATokens)) and not IsCode(ATokens[Result]) do
    Inc(Result);
end;

function PrevCode(const ATokens: TTokens; AIndex: Integer): Integer;
begin
  Result := AIndex - 1;
  while (Result >= 0) and not IsCode(ATokens[Result]) do
    Dec(Result);
end;

function Before(const A, B: TTextPosition): Boolean;
begin
  Result := (A.Line < B.Line) or ((A.Line = B.Line) and (A.Character < B.Character));
end;

{ /header }

/// <summary>Vorlage mit ersetzten Platzhaltern, Zeilenenden wie ALineBreak.</summary>
function ExpandHeader(const ATemplate, AUnitName, ALineBreak: string): string;
var
  Author: string;
begin
  Author := GetEnvironmentVariable('USERNAME');
  if Author = '' then
    Author := GetEnvironmentVariable('USER');
  Result := StringReplace(ATemplate, '{unit}', AUnitName, [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '{jahr}', IntToStr(CurrentYear), [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '{autor}', Author, [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(StringReplace(Result, #13#10, #10, [rfReplaceAll]), #10, ALineBreak, [rfReplaceAll]);
end;

/// <summary>Letzte Jahreszahl (19xx/20xx) in AText ab 1; 0 ohne.</summary>
function LastYear(const AText: string; out AYear: Integer): Integer;
var
  Index: Integer;
begin
  Result := 0;
  AYear := 0;
  for Index := 1 to Length(AText) - 3 do
    if CharInSet(AText[Index], ['1', '2']) and CharInSet(AText[Index + 1], ['0', '9']) and
      CharInSet(AText[Index + 2], ['0'..'9']) and CharInSet(AText[Index + 3], ['0'..'9']) and
      ((Index = 1) or not CharInSet(AText[Index - 1], ['0'..'9'])) and
      ((Index + 4 > Length(AText)) or not CharInSet(AText[Index + 4], ['0'..'9'])) then
    begin
      Result := Index;
      AYear := StrToInt(Copy(AText, Index, 4));
    end;
end;

function ExecuteHeader(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  Tokens: TTokens;
  First, Index, Last, YearPos, Year: Integer;
  Template, Header, HeaderText, Updated: string;
begin
  AEdits := nil;
  Source := TCommandSource.Create(AContext);
  try
    Tokens := Source.Tree.Tokens;
    First := 0;
    while (First <= High(Tokens)) and not IsCode(Tokens[First]) do
      Inc(First);
    if (First > High(Tokens)) or (Source.Tree.Root = nil) or (Source.Tree.Root.Name = '') then
      Exit(Fail('/header gilt nur in einer Unit', AReason));
    // Kommentare vor "unit" bilden den vorhandenen Kopf; dort nur das Jahr fortschreiben.
    HeaderText := '';
    for Index := 0 to First - 1 do
      if Tokens[Index].Kind = TPascalTokenKind.Comment then
        HeaderText := HeaderText + Tokens[Index].Text + #10;
    if HeaderText <> '' then
    begin
      // Kommentar mit der letzten Jahreszahl im Kopf.
      Last := -1;
      for Index := 0 to First - 1 do
        if (Tokens[Index].Kind = TPascalTokenKind.Comment) and (LastYear(Tokens[Index].Text, Year) > 0) then
          Last := Index;
      if Last >= 0 then
      begin
        YearPos := LastYear(Tokens[Last].Text, Year);
        if Year < CurrentYear then
        begin
          // 2019 wird 2019-2026, 2019-2025 wird 2019-2026.
          if (YearPos > 1) and (Tokens[Last].Text[YearPos - 1] = '-') then
            Updated := Copy(Tokens[Last].Text, 1, YearPos - 1) + IntToStr(CurrentYear) +
              Copy(Tokens[Last].Text, YearPos + 4, MaxInt)
          else
            Updated := Copy(Tokens[Last].Text, 1, YearPos + 3) + '-' + IntToStr(CurrentYear) +
              Copy(Tokens[Last].Text, YearPos + 4, MaxInt);
          AEdits := [TTextEdit.Create(TTextRange.Create(Tokens[Last].StartPos, Tokens[Last].EndPos), Updated)];
        end;
      end;
      AEdits := AEdits + [Source.RemoveCommand];
      Exit(True);
    end;
    Template := '';
    if AContext.Host <> nil then
      Template := AContext.Host.HeaderTemplate(AContext.Uri);
    if Template = '' then
      Template := DefaultHeaderTemplate;
    Header := ExpandHeader(Template, Source.Tree.Root.Name, Source.LineBreak) + Source.LineBreak;
    if Source.Line = 0 then
      AEdits := [TTextEdit.Create(TTextRange.Create(0, 0, 1, 0), Header)]
    else
      AEdits := [TTextEdit.Create(TTextRange.Create(0, 0, 0, 0), Header), Source.RemoveCommand];
    Result := True;
  finally
    Source.Free;
  end;
end;

{ /deprecated }

/// <summary>Token-Index des abschließenden ";" der Routinendeklaration ab AStart samt Direktiven.</summary>
function RoutineEnd(const ATokens: TTokens; AStart: Integer; out ADeprecated: Boolean): Integer;
var
  Index, Depth, Next: Integer;
begin
  ADeprecated := False;
  Depth := 0;
  Index := AStart;
  while Index <= High(ATokens) do
  begin
    if ATokens[Index].IsSymbol('(') or ATokens[Index].IsSymbol('[') then
      Inc(Depth)
    else if ATokens[Index].IsSymbol(')') or ATokens[Index].IsSymbol(']') then
      Dec(Depth)
    else if (Depth = 0) and ATokens[Index].IsSymbol(';') then
      Break;
    Inc(Index);
  end;
  if Index > High(ATokens) then
    Exit(-1);
  Result := Index;
  Next := NextCode(ATokens, Result);
  while (Next <= High(ATokens)) and MatchText(ATokens[Next].Text, Directives) do
  begin
    if SameText(ATokens[Next].Text, 'deprecated') then
      ADeprecated := True;
    Index := Next;
    while (Index <= High(ATokens)) and not ATokens[Index].IsSymbol(';') do
      Inc(Index);
    if Index > High(ATokens) then
      Break;
    Result := Index;
    Next := NextCode(ATokens, Result);
  end;
end;

/// <summary>Erstes Token einer Routinendeklaration in Zeile ALine; -1 ohne.</summary>
function RoutineTokenAt(const ATokens: TTokens; ALine: Integer): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(ATokens) do
    if (ATokens[Index].StartPos.Line = ALine) and MatchText(ATokens[Index].Text, RoutineKeywords) then
      Exit(Index);
  Result := -1;
end;

/// <summary>Name hinter procedure/function usw. ab AStart, mit Punkten.</summary>
function RoutineName(const ATokens: TTokens; AStart: Integer): string;
var
  Index: Integer;
begin
  Index := AStart;
  while (Index <= High(ATokens)) and MatchText(ATokens[Index].Text, RoutineKeywords) do
    Index := NextCode(ATokens, Index);
  Result := '';
  while Index <= High(ATokens) do
  begin
    Result := Result + ATokens[Index].Text;
    Index := NextCode(ATokens, Index);
    if (Index > High(ATokens)) or not ATokens[Index].IsSymbol('.') then
      Break;
    Result := Result + '.';
    Index := NextCode(ATokens, Index);
  end;
end;

/// <summary>Zeile der Deklaration zu einer Implementierung (Methode in der Klasse, Routine im interface);
/// -1, wenn die Routine nur hier steht.</summary>
function DeclarationLine(ASource: TCommandSource; const AName: string; AImplLine: Integer): Integer;
var
  Symbol: TIndexSymbol;
  Container, Name: string;
  Dot: Integer;
begin
  Dot := LastDelimiter('.', AName);
  Container := Copy(AName, 1, Dot - 1);
  if LastDelimiter('.', Container) > 0 then
    Container := Copy(Container, LastDelimiter('.', Container) + 1, MaxInt);
  Name := Copy(AName, Dot + 1, MaxInt);
  for Symbol in ASource.UnitIndex.Symbols do
    if (Symbol.Kind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_, TIndexSymbolKind.Routine]) and
      SameText(Symbol.Name, Name) and SameText(Symbol.Container, Container) and
      (Symbol.Range.StartPos.Line < AImplLine) and
      ((Container <> '') or Symbol.InInterface) then
      Exit(Symbol.Range.StartPos.Line);
  Result := -1;
end;

function FindTypeDecl(ANode: TSyntaxNode; ALine: Integer): TSyntaxNode;
var
  Index: Integer;
begin
  if (ANode.Kind = TSyntaxKind.TypeDecl) and (ANode.StartPos.Line = ALine) then
    Exit(ANode);
  for Index := 0 to ANode.ChildCount - 1 do
    if (ANode[Index].StartPos.Line <= ALine) and (ANode[Index].EndPos.Line >= ALine) then
    begin
      Result := FindTypeDecl(ANode[Index], ALine);
      if Result <> nil then
        Exit;
    end;
  Result := nil;
end;

function ExecuteDeprecated(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>;
  out AReason: string): Boolean;
var
  Source: TCommandSource;
  Tokens: TTokens;
  Target, Index, Stop, Prev, DeclLine: Integer;
  Present: Boolean;
  Hint, Remark, Name: string;
  TypeNode: TSyntaxNode;
  Directive: TTextEdit;
begin
  AEdits := nil;
  Source := TCommandSource.Create(AContext);
  try
    Tokens := Source.Tree.Tokens;
    // Erstes Code-Token unter dem Befehl; Attribute [..] davor überspringen.
    Target := -1;
    for Index := 0 to High(Tokens) do
      if (Tokens[Index].StartPos.Line > Source.Line) and IsCode(Tokens[Index]) then
      begin
        Target := Index;
        Break;
      end;
    while (Target >= 0) and (Target <= High(Tokens)) and Tokens[Target].IsSymbol('[') do
    begin
      while (Target <= High(Tokens)) and not Tokens[Target].IsSymbol(']') do
        Inc(Target);
      Target := NextCode(Tokens, Target);
    end;
    if (Target < 0) or (Target > High(Tokens)) then
      Exit(Fail('/deprecated gehört über eine Routine oder einen Typ', AReason));
    Hint := ' deprecated';
    if AContext.Arguments <> '' then
      Hint := Hint + ' ' + QuotedStr(AContext.Arguments);
    if MatchText(Tokens[Target].Text, RoutineKeywords) then
    begin
      Name := RoutineName(Tokens, Target);
      DeclLine := DeclarationLine(Source, Name, Tokens[Target].StartPos.Line);
      // Die Direktive steht nur an der Deklaration, nie an der Implementierung.
      if DeclLine >= 0 then
        Target := RoutineTokenAt(Tokens, DeclLine);
      if Target < 0 then
        Exit(Fail('Deklaration von ' + Name + ' nicht gefunden', AReason));
      Stop := RoutineEnd(Tokens, Target, Present);
      if Stop < 0 then
        Exit(Fail('Deklaration von ' + Name + ' ist unvollständig', AReason));
      Directive := TTextEdit.Create(TTextRange.Create(Tokens[Stop].EndPos, Tokens[Stop].EndPos), Hint + ';');
    end
    else
    begin
      TypeNode := FindTypeDecl(Source.Tree.Root, Tokens[Target].StartPos.Line);
      if TypeNode = nil then
        Exit(Fail('/deprecated gehört über eine Routine oder einen Typ', AReason));
      Stop := -1;
      for Index := Target to High(Tokens) do
      begin
        if Before(TypeNode.EndPos, Tokens[Index].EndPos) then
          Break;
        if Tokens[Index].IsSymbol(';') then
          Stop := Index;
      end;
      if Stop < 0 then
        Exit(Fail('Typdeklaration ist unvollständig', AReason));
      Prev := PrevCode(Tokens, Stop);
      if (Prev >= 0) and (Tokens[Prev].Kind = TPascalTokenKind.StringLiteral) then
        Prev := PrevCode(Tokens, Prev);
      Present := (Prev >= 0) and SameText(Tokens[Prev].Text, 'deprecated');
      Directive := TTextEdit.Create(TTextRange.Create(Tokens[Stop].StartPos, Tokens[Stop].StartPos), Hint);
    end;
    if Present then
      Exit(Fail('Die Deklaration ist schon als deprecated markiert', AReason));
    DeclLine := Tokens[Target].StartPos.Line;
    Remark := Source.Indent(DeclLine) + '/// <remarks>Veraltet';
    if AContext.Arguments <> '' then
      Remark := Remark + ': ' + AContext.Arguments;
    Remark := Remark + '</remarks>' + Source.LineBreak;
    if DeclLine = Source.Line + 1 then
      AEdits := [TTextEdit.Create(TTextRange.Create(Source.Line, 0, Source.Line + 1, 0), Remark), Directive]
    else
      AEdits := [TTextEdit.Create(TTextRange.Create(DeclLine, 0, DeclLine, 0), Remark), Directive,
        Source.RemoveCommand];
    Result := True;
  finally
    Source.Free;
  end;
end;

{ /region-all }

type
  TBody = record
    Name: string;
    FirstLine: Integer;
    LastLine: Integer;
    Group: Integer;
  end;

const
  GroupNames: array[0..5] of string = ('Ereignis-Handler', 'Published', 'Public', 'Protected', 'Private',
    'Getter und Setter');

function GroupOf(ASource: TCommandSource; const AClass: TIndexSymbol; ARoutine: TSyntaxNode): Integer;
var
  Name, Header: string;
  Symbol: TIndexSymbol;
  Index: Integer;
begin
  Name := Copy(ARoutine.Name, LastDelimiter('.', ARoutine.Name) + 1, MaxInt);
  Header := '';
  for Index := ARoutine.StartPos.Line to ARoutine.StartPos.Line + 2 do
    if Index <= High(ASource.Lines) then
      Header := Header + ASource.Lines[Index];
  if ContainsText(Header, 'Sender: TObject') then
    Exit(0);
  if (Length(Name) > 3) and (StartsText('Get', Name) or StartsText('Set', Name)) and CharInSet(Name[4], ['A'..'Z']) then
    Exit(5);
  for Symbol in ASource.UnitIndex.Symbols do
    if SameText(Symbol.Name, Name) and SameText(Symbol.Container, AClass.Name) and
      (Symbol.Range.StartPos.Line > AClass.Range.StartPos.Line) and
      (Symbol.Range.EndPos.Line <= AClass.Range.EndPos.Line) then
      case Symbol.Visibility of
        TIndexVisibility.Published:
          Exit(1);
        TIndexVisibility.Public:
          Exit(2);
        TIndexVisibility.Protected, TIndexVisibility.StrictProtected:
          Exit(3);
      else
        Exit(4);
      end;
  Result := 4;
end;

function ExecuteRegionAll(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>;
  out AReason: string): Boolean;
var
  Source: TCommandSource;
  AClass: TIndexSymbol;
  Section: TSyntaxNode;
  Bodies: TArray<TBody>;
  Body: TBody;
  Index, Group, Line, Stop: Integer;
  Text, Block: string;
  First: Boolean;
begin
  AEdits := nil;
  Source := TCommandSource.Create(AContext);
  try
    if not Source.ClassAt(AClass) then
      Exit(Fail('/region-all gehört in die Deklaration der Klasse', AReason));
    Section := Source.Tree.Root.FindChild(TSyntaxKind.ImplementationSection);
    Bodies := nil;
    if Section <> nil then
      for Index := 0 to Section.ChildCount - 1 do
        if (Section[Index].Kind = TSyntaxKind.RoutineDecl) and StartsText(AClass.Name + '.', Section[Index].Name) and
          (Pos('.', Copy(Section[Index].Name, Length(AClass.Name) + 2, MaxInt)) = 0) then
        begin
          Body.Name := Section[Index].Name;
          Body.LastLine := Section[Index].EndPos.Line;
          // Kommentare direkt über der Methode gehören dazu.
          Body.FirstLine := Section[Index].StartPos.Line;
          while (Body.FirstLine > 0) and (Body.FirstLine - 1 <> Source.Line) and
            (StartsStr('//', TrimLeft(Source.Lines[Body.FirstLine - 1])) or
            StartsStr('{', TrimLeft(Source.Lines[Body.FirstLine - 1])) and
            not StartsText('{$', TrimLeft(Source.Lines[Body.FirstLine - 1]))) do
            Dec(Body.FirstLine);
          Body.Group := GroupOf(Source, AClass, Section[Index]);
          Bodies := Bodies + [Body];
        end;
    if Length(Bodies) < 2 then
      Exit(Fail(Format('%s hat zu wenige Methoden für Regionen', [AClass.Name]), AReason));
    for Line := Bodies[0].FirstLine to Bodies[High(Bodies)].LastLine do
      if StartsText('{$REGION', TrimLeft(Source.Lines[Line])) then
        Exit(Fail(Format('Die Methoden von %s stehen schon in Regionen', [AClass.Name]), AReason));
    for Body in Bodies do
      if (Source.Line >= Body.FirstLine) and (Source.Line <= Body.LastLine) then
        Exit(Fail('/region-all gehört in die Deklaration der Klasse', AReason));
    Text := '';
    First := True;
    for Group := 0 to High(GroupNames) do
    begin
      Block := '';
      for Body in Bodies do
        if Body.Group = Group then
        begin
          if Block <> '' then
            Block := Block + Source.LineBreak;
          for Line := Body.FirstLine to Body.LastLine do
            Block := Block + Source.Lines[Line] + Source.LineBreak;
        end;
      if Block = '' then
        Continue;
      if not First then
        Text := Text + Source.LineBreak;
      First := False;
      Text := Text + Format('{$REGION ''%s''}', [GroupNames[Group]]) + Source.LineBreak + Block + '{$ENDREGION}' +
        Source.LineBreak;
    end;
    // Erste Methode wird durch den ganzen Block ersetzt, die übrigen entfallen samt Leerzeile danach.
    for Index := 0 to High(Bodies) do
    begin
      Stop := Bodies[Index].LastLine + 1;
      if (Index > 0) and (Stop <= High(Source.Lines)) and (Trim(Source.Lines[Stop]) = '') and
        (Stop <> Source.Line) then
        Inc(Stop);
      if Index = 0 then
        AEdits := AEdits + [TTextEdit.Create(TTextRange.Create(Bodies[0].FirstLine, 0, Stop, 0), Text)]
      else
        AEdits := AEdits + [TTextEdit.Create(TTextRange.Create(Bodies[Index].FirstLine, 0, Stop, 0), '')];
    end;
    AEdits := AEdits + [Source.RemoveCommand];
    Result := True;
  finally
    Source.Free;
  end;
end;

function Command(const AName, ASummary, AExample: string; const AExecute: TSlashExecute): TSlashCommand;
begin
  Result.Name := AName;
  Result.Summary := ASummary;
  Result.Example := AExample;
  Result.Execute := AExecute;
end;

procedure RegisterDocumentationCommands(ARegistry: TSlashCommandRegistry);
begin
  ARegistry.Register(Command('header', 'Dateikopf setzen bzw. Jahr fortschreiben', '/header', ExecuteHeader));
  ARegistry.Register(Command('deprecated', 'Deklaration darunter als veraltet markieren', '/deprecated Grund',
    ExecuteDeprecated));
  ARegistry.Register(Command('region-all', 'Methoden der Klasse in Regionen ordnen', '/region-all',
    ExecuteRegionAll));
end;

end.
