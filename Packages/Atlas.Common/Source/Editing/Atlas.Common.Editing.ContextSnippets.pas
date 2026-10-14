unit Atlas.Common.Editing.ContextSnippets;

// Kontextabhängige Code-Vorlagen der Vervollständigung (#51). Anders als die
// festen Vorlagen des Plugins kennen sie Klasse, Felder und Sichtbarkeit:
//
//   prop     in einer Klassendeklaration je Feld FName ohne Property: Property Name
//            an der Stelle, Setter-Deklaration im private-Abschnitt und Setter-Rumpf
//            mit Änderungsprüfung (TSetterGenerator, derselbe Erzeuger wie /prop)
//   changed  im Rumpf eines Setters SetName, der FName noch nicht zuweist: Prüfung,
//            Zuweisung und Benachrichtigung
//   create   im Rumpf eines Konstruktors: noch nicht erzeugte Objektfelder anlegen
//            (Komponenten mit Self als Owner)
//   free     im Rumpf eines Destruktors: erzeugte, noch nicht freigegebene Felder
//            in umgekehrter Reihenfolge freigeben (wie /dtor)
//
// Angeboten wird nur, wenn vor dem Cursor in der Zeile höchstens ein Wort steht und
// dahinter nichts. Der Text ist ein LSP-Snippet (${1:Vorgabe}, $0; "$", "}" und "\"
// mit "\" maskiert). Clients ohne snippetSupport bekommen ToPlain.

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Editing.SlashCommands;

type
  TContextSnippet = record
    /// <summary>Kürzel, nach dem die Liste filtert: prop, changed, create, free.</summary>
    Prefix: string;
    /// <summary>Anzeige, z. B. "prop Caption".</summary>
    Name: string;
    Description: string;
    /// <summary>LSP-Snippet; Zeilen mit #10, ohne Einrückung der Cursorzeile.</summary>
    Text: string;
    /// <summary>Weitere Änderungen (Setter-Deklaration und -Rumpf); ohne Platzhalter.</summary>
    AdditionalEdits: TArray<TRuleEdit>;
  end;

  TContextSnippets = class
  public
    /// <summary>Vorlagen für die Cursorzeile AContext.Line bei Zeichen ACharacter. AContext.Text enthält die Zeile
    /// mit dem getippten Wort; AContext.Index für Vorfahren aus anderen Units (nil ohne).</summary>
    class function At(const AContext: TSlashContext; ACharacter: Integer): TArray<TContextSnippet>; static;
    /// <summary>Maskiert "\", "$" und "}" für ein LSP-Snippet.</summary>
    class function Escape(const AText: string): string; static;
    /// <summary>Klartext zu einem LSP-Snippet: Platzhalter und ${NAME:…} werden zu ihrer Vorgabe, Tabstopps
    /// entfallen, Masken werden aufgelöst; "$" vor einem Buchstaben bleibt Text.</summary>
    class function ToPlain(const ASnippet: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Editing.CommandSource,
  Atlas.Common.Editing.ClassMembers,
  Atlas.Common.Editing.ClassCommands,
  Atlas.Common.Editing.TypeCommands;

function IsIdentChar(C: Char): Boolean;
begin
  Result := CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_']);
end;

/// <summary>Typ mit Typargumenten: TObjectList&lt;TKunde&gt;.</summary>
function FullType(const AField: TIndexSymbol): string;
begin
  Result := AField.TypeName;
  if AField.TypeArgs <> '' then
    Result := Result + '<' + AField.TypeArgs + '>';
end;

/// <summary>Zeilen des Rumpfs zwischen begin und end ohne die Cursorzeile, verbunden mit #10.</summary>
function BodyText(ASource: TCommandSource; ABlock: TSyntaxNode): string;
var
  Index: Integer;
begin
  Result := '';
  for Index := ABlock.StartPos.Line + 1 to ABlock.EndPos.Line - 1 do
    if Index <> ASource.Line then
      Result := Result + ASource.Lines[Index] + #10;
end;

/// <summary>Kommt AName als ganzes Wort in AText vor (ohne Groß/Klein)?</summary>
function Mentions(const AText, AName: string): Boolean;
var
  Upper, Name: string;
  Found, After: Integer;
begin
  Upper := UpperCase(AText);
  Name := UpperCase(AName);
  Found := Pos(Name, Upper);
  while Found > 0 do
  begin
    After := Found + Length(Name);
    if ((Found = 1) or not IsIdentChar(Upper[Found - 1])) and
      ((After > Length(Upper)) or not IsIdentChar(Upper[After])) then
      Exit(True);
    Found := PosEx(Name, Upper, Found + 1);
  end;
  Result := False;
end;

function Snippet(const APrefix, AName, ADescription, AText: string;
  const AEdits: TArray<TRuleEdit>): TContextSnippet;
begin
  Result.Prefix := APrefix;
  Result.Name := AName;
  Result.Description := ADescription;
  Result.Text := AText;
  Result.AdditionalEdits := AEdits;
end;

function NotifyText(const ACall: string): string;
begin
  if ACall = '' then
    Result := 'ohne Benachrichtigung'
  else
    Result := 'ruft ' + ACall + ' auf';
end;

{ prop }

function PropertyItems(ASource: TCommandSource; const AContext: TSlashContext;
  const AClass: TIndexSymbol): TArray<TContextSnippet>;
var
  Field, Member: TIndexSymbol;
  Name, Setter, TypeText, Call, Indent, LB: string;
  Edits: TArray<TRuleEdit>;
  EndLine: Integer;
begin
  Result := nil;
  Call := TSetterGenerator.NotifyCall(ASource, AContext.Index, AClass);
  LB := ASource.LineBreak;
  EndLine := AClass.Range.EndPos.Line;
  Indent := ASource.Indent(EndLine);
  for Field in Members(ASource, AClass, [TIndexSymbolKind.Field]) do
  begin
    if (Length(Field.Name) < 2) or not CharInSet(Field.Name[1], ['F', 'f']) or (Field.TypeName = '') then
      Continue;
    Name := Copy(Field.Name, 2, MaxInt);
    if FindMember(ASource, AClass, Name, [TIndexSymbolKind.Property_], Member) then
      Continue;
    Setter := 'Set' + Name;
    TypeText := FullType(Field);
    Edits := nil;
    if not FindMember(ASource, AClass, Setter, [TIndexSymbolKind.Method], Member) then
      // Wie /changed: eigener private-Abschnitt vor "end", weil Felder vor Methoden stehen müssen.
      Edits := [ASource.BeforeLine(EndLine, Indent + 'private' + LB + Indent + '  ' +
        Format('procedure %s(const Value: %s);', [Setter, TypeText])),
        ASource.AddBody(AClass.Name, Format('procedure %s.%s(const Value: %s);', [AClass.Name, Setter, TypeText]) +
        LB + TSetterGenerator.Body(Field.Name, 'Value', Call, LB))];
    Result := Result + [Snippet('prop', 'prop ' + Name,
      Format('Property %s: %s mit Setter %s, der auf Änderung prüft und %s', [Name, TypeText, Setter,
      NotifyText(Call)]),
      Format('property ${1:%s}: %s read %s write %s;$0', [TContextSnippets.Escape(Name),
      TContextSnippets.Escape(TypeText), Field.Name, Setter]), Edits)];
  end;
end;

{ changed }

function SetterItems(ASource: TCommandSource; const AContext: TSlashContext; const AClass: TIndexSymbol;
  ARoutine, ABlock: TSyntaxNode; const AMethod: string): TArray<TContextSnippet>;
var
  Prop, Member: TIndexSymbol;
  Field, Value, Call, Text, Line: string;
  Found: Boolean;
begin
  Result := nil;
  // Feld: read-Teil der Property, die über AMethod schreibt; sonst FName zu SetName.
  Field := '';
  for Prop in Members(ASource, AClass, [TIndexSymbolKind.Property_]) do
    if SameText(Accessor(RangeText(ASource.Lines, Prop.Range), 'write'), AMethod) then
    begin
      Field := Accessor(RangeText(ASource.Lines, Prop.Range), 'read');
      Break;
    end;
  if (Field = '') and StartsText('Set', AMethod) and (Length(AMethod) > 3) then
    Field := 'F' + Copy(AMethod, 4, MaxInt);
  if (Field = '') or not FindMember(ASource, AClass, Field, [TIndexSymbolKind.Field], Member) then
    Exit;
  Field := Member.Name;
  Value := ParameterNames(RoutineSignature(ASource.Lines[ARoutine.StartPos.Line]));
  if (Value = '') or (Pos(',', Value) > 0) or Mentions(BodyText(ASource, ABlock), Field) then
    Exit;
  Call := TSetterGenerator.NotifyCall(ASource, AContext.Index, AClass);
  // Die Benachrichtigung ist der Platzhalter; ohne bleibt nur die Endposition.
  if Call <> '' then
    Call := '${1:' + Call + '}';
  Text := '';
  Found := False;
  for Line in TSetterGenerator.Statements(Field, Value, Call) do
  begin
    if Found then
      Text := Text + #10;
    Text := Text + Line;
    Found := True;
  end;
  Result := [Snippet('changed', 'changed ' + Field, Format('%s nur bei Änderung setzen; %s', [Field,
    NotifyText(TSetterGenerator.NotifyCall(ASource, AContext.Index, AClass))]), Text + '$0', nil)];
end;

{ create }

function ConstructorItems(ASource: TCommandSource; const AContext: TSlashContext; const AClass: TIndexSymbol;
  ABlock: TSyntaxNode): TArray<TContextSnippet>;
var
  Field: TIndexSymbol;
  Created: TArray<string>;
  Body, Text, Owner: string;
  Lines: TArray<string>;
  Number: Integer;
  OwnerKnown: Boolean;
begin
  Result := nil;
  Body := BodyText(ASource, ABlock);
  Created := CreatedFields(ASource, AClass.Name);
  OwnerKnown := IsComponentType(ASource, AContext.Index, AClass.Name);
  Lines := nil;
  Number := 0;
  for Field in Members(ASource, AClass, [TIndexSymbolKind.Field]) do
  begin
    if (IndexText(Field.Name, Created) >= 0) or Mentions(Body, Field.Name) or
      not IsObjectField(ASource, AContext.Index, Field) then
      Continue;
    Inc(Number);
    Owner := '';
    if OwnerKnown and IsComponentType(ASource, AContext.Index, Field.TypeName) then
      Owner := '(Self)';
    Lines := Lines + [Format('%s := ${%d:%s}.Create%s;', [Field.Name, Number,
      TContextSnippets.Escape(FullType(Field)), Owner])];
  end;
  if Number = 0 then
    Exit;
  if not Mentions(Body, 'inherited') then
    Lines := ['inherited;'] + Lines;
  Text := string.Join(#10, Lines) + '$0';
  Result := [Snippet('create', 'create', Format('%d Objektfelder von %s erzeugen', [Number, AClass.Name]), Text,
    nil)];
end;

{ free }

function DestructorItems(ASource: TCommandSource; const AClass: TIndexSymbol;
  ABlock: TSyntaxNode): TArray<TContextSnippet>;
var
  Created, Lines: TArray<string>;
  Body: string;
  Index: Integer;
begin
  Result := nil;
  Body := BodyText(ASource, ABlock);
  Created := CreatedFields(ASource, AClass.Name);
  Lines := nil;
  // In umgekehrter Reihenfolge der Erzeugung freigeben, wie /dtor.
  for Index := High(Created) downto 0 do
    if not Mentions(Body, Created[Index]) then
      Lines := Lines + [Format('FreeAndNil(%s);', [Created[Index]])];
  if Length(Lines) = 0 then
    Exit;
  Result := [Snippet('free', 'free', Format('%d erzeugte Felder von %s freigeben', [Integer(Length(Lines)),
    AClass.Name]), string.Join(#10, Lines) + '$0', nil)];
  if not Mentions(Body, 'inherited') then
    Result[0].Text := Result[0].Text + #10'inherited;';
end;

{ TContextSnippets }

class function TContextSnippets.At(const AContext: TSlashContext; ACharacter: Integer): TArray<TContextSnippet>;
var
  Source: TCommandSource;
  ClassSymbol: TIndexSymbol;
  Routine, Block: TSyntaxNode;
  Before, Head, Method: string;
  Index, Dot: Integer;
begin
  Result := nil;
  // Höchstens ein Wort vor dem Cursor, nichts dahinter.
  if (ACharacter < 0) or (ACharacter > Length(AContext.LineText)) or
    (Trim(Copy(AContext.LineText, ACharacter + 1, MaxInt)) <> '') then
    Exit;
  Before := TrimLeft(Copy(AContext.LineText, 1, ACharacter));
  for Index := 1 to Length(Before) do
    if not IsIdentChar(Before[Index]) then
      Exit;
  Source := TCommandSource.Create(AContext);
  try
    if not Source.ClassAt(ClassSymbol) then
      Exit;
    Routine := Source.RoutineAt;
    if Routine = nil then
    begin
      // In der Klassendeklaration.
      if (ClassSymbol.Range.StartPos.Line < AContext.Line) and (ClassSymbol.Range.EndPos.Line > AContext.Line) then
        Result := PropertyItems(Source, AContext, ClassSymbol);
      Exit;
    end;
    Block := Routine.FindChild(TSyntaxKind.Block);
    if (Block = nil) or (Block.StartPos.Line >= AContext.Line) or (Block.EndPos.Line <= AContext.Line) then
      Exit;
    Dot := LastDelimiter('.', Routine.Name);
    Method := Copy(Routine.Name, Dot + 1, MaxInt);
    Head := LowerCase(TrimLeft(Source.Lines[Routine.StartPos.Line]));
    if StartsStr('constructor ', Head) then
      Result := ConstructorItems(Source, AContext, ClassSymbol, Block)
    else if StartsStr('destructor ', Head) then
      Result := DestructorItems(Source, ClassSymbol, Block)
    else if StartsStr('procedure ', Head) then
      Result := SetterItems(Source, AContext, ClassSymbol, Routine, Block, Method);
  finally
    Source.Free;
  end;
end;

class function TContextSnippets.Escape(const AText: string): string;
var
  C: Char;
begin
  Result := '';
  for C in AText do
    if CharInSet(C, ['\', '$', '}']) then
      Result := Result + '\' + C
    else
      Result := Result + C;
end;

/// <summary>Liest ab AIndex bis zum passenden "}" (oder Textende) und gibt den Klartext zurück; AIndex steht danach
/// hinter dem "}".</summary>
function PlainUntilClose(const AText: string; var AIndex: Integer; AInside: Boolean): string;
var
  Start: Integer;
begin
  Result := '';
  while AIndex <= Length(AText) do
  begin
    case AText[AIndex] of
      '\':
        begin
          if (AIndex < Length(AText)) and CharInSet(AText[AIndex + 1], ['\', '$', '}', ',', '|']) then
          begin
            Result := Result + AText[AIndex + 1];
            Inc(AIndex, 2);
          end
          else
          begin
            Result := Result + '\';
            Inc(AIndex);
          end;
          Continue;
        end;
      '}':
        if AInside then
        begin
          Inc(AIndex);
          Exit;
        end;
      '$':
        if AIndex < Length(AText) then
        begin
          // $1; "$" vor einem Buchstaben bleibt Text ($FF).
          if CharInSet(AText[AIndex + 1], ['0'..'9']) then
          begin
            Inc(AIndex);
            while (AIndex <= Length(AText)) and IsIdentChar(AText[AIndex]) do
              Inc(AIndex);
            Continue;
          end;
          // ${1}, ${1:Vorgabe}, ${1|a,b|}, ${NAME:Vorgabe}
          if AText[AIndex + 1] = '{' then
          begin
            Inc(AIndex, 2);
            while (AIndex <= Length(AText)) and IsIdentChar(AText[AIndex]) do
              Inc(AIndex);
            if (AIndex <= Length(AText)) and (AText[AIndex] = ':') then
            begin
              Inc(AIndex);
              Result := Result + PlainUntilClose(AText, AIndex, True);
            end
            else if (AIndex <= Length(AText)) and (AText[AIndex] = '|') then
            begin
              // Auswahl: die erste Möglichkeit.
              Inc(AIndex);
              Start := AIndex;
              while (AIndex <= Length(AText)) and not CharInSet(AText[AIndex], [',', '|']) do
                Inc(AIndex);
              Result := Result + Copy(AText, Start, AIndex - Start);
              while (AIndex <= Length(AText)) and (AText[AIndex] <> '}') do
                Inc(AIndex);
              Inc(AIndex);
            end
            else
            begin
              while (AIndex <= Length(AText)) and (AText[AIndex] <> '}') do
                Inc(AIndex);
              Inc(AIndex);
            end;
            Continue;
          end;
        end;
    end;
    Result := Result + AText[AIndex];
    Inc(AIndex);
  end;
end;

class function TContextSnippets.ToPlain(const ASnippet: string): string;
var
  Index: Integer;
begin
  Index := 1;
  Result := PlainUntilClose(ASnippet, Index, False);
end;

end.
