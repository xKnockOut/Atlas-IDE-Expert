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
  Atlas.Common.Documents.Contract,
  Atlas.Common.Editing.Contract;

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
    AdditionalEdits: TArray<TTextEdit>;
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
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Editing.CommandSource,
  Atlas.Common.Editing.ClassMembers,
  Atlas.Common.Editing.ClassCommands,
  Atlas.Common.Editing.TypeCommands,
  Atlas.Text.Chars;

/// <summary>Typ mit Typargumenten: TObjectList&lt;TKunde&gt;.</summary>
function FullType(const AField: TIndexSymbol): string;
begin
  Result := AField.TypeName;
  if AField.TypeArgs <> '' then
  begin
    Result := Result + '<' + AField.TypeArgs + '>';
  end;
end;

/// <summary>Zeilen des Rumpfs zwischen begin und end ohne die Cursorzeile, verbunden mit #10.</summary>
function BodyText(ASource: TCommandSource; ABlock: TSyntaxNode): string;
var
  Index: Integer;
begin
  Result := '';
  for Index := ABlock.StartPos.Line + 1 to ABlock.EndPos.Line - 1 do
  begin
    if Index <> ASource.Line then
    begin
      Result := Result + ASource.Lines[Index] + #10;
    end;
  end;
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
    if ((Found = 1) or not TTextChars.IsAsciiIdentChar(Upper[Found - 1])) and
      ((After > Length(Upper)) or not TTextChars.IsAsciiIdentChar(Upper[After])) then
    begin
      Exit(True);
    end;
    Found := PosEx(Name, Upper, Found + 1);
  end;
  Result := False;
end;

function Snippet(const APrefix, AName, ADescription, AText: string;
  const AEdits: TArray<TTextEdit>): TContextSnippet;
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
  begin
    Result := 'ohne Benachrichtigung';
  end
  else
  begin
    Result := 'ruft ' + ACall + ' auf';
  end;
end;

{ prop }

function PropertyItems(ASource: TCommandSource; const AContext: TSlashContext;
  const AClass: TIndexSymbol): TArray<TContextSnippet>;
var
  Field, Member: TIndexSymbol;
  Name, Setter, TypeText, Call, Indent, LB: string;
  Edits: TArray<TTextEdit>;
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
    begin
      Continue;
    end;
    Name := Copy(Field.Name, 2, MaxInt);
    if FindMember(ASource, AClass, Name, [TIndexSymbolKind.Property_], Member) then
    begin
      Continue;
    end;
    Setter := 'Set' + Name;
    TypeText := FullType(Field);
    Edits := nil;
    if not FindMember(ASource, AClass, Setter, [TIndexSymbolKind.Method], Member) then
    begin
      // Wie /changed: eigener private-Abschnitt vor "end", weil Felder vor Methoden stehen müssen.
      Edits := [ASource.BeforeLine(EndLine, Indent + 'private' + LB + Indent + '  ' +
        Format('procedure %s(const Value: %s);', [Setter, TypeText])),
        ASource.AddBody(AClass.Name, Format('procedure %s.%s(const Value: %s);', [AClass.Name, Setter, TypeText]) +
        LB + TSetterGenerator.Body(Field.Name, 'Value', Call, LB))];
    end;
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
  begin
    if SameText(Accessor(RangeText(ASource.Lines, Prop.Range), 'write'), AMethod) then
    begin
      Field := Accessor(RangeText(ASource.Lines, Prop.Range), 'read');
      Break;
    end;
  end;
  if (Field = '') and StartsText('Set', AMethod) and (Length(AMethod) > 3) then
  begin
    Field := 'F' + Copy(AMethod, 4, MaxInt);
  end;
  if (Field = '') or not FindMember(ASource, AClass, Field, [TIndexSymbolKind.Field], Member) then
  begin
    Exit;
  end;
  Field := Member.Name;
  Value := ParameterNames(RoutineSignature(ASource.Lines[ARoutine.StartPos.Line]));
  if (Value = '') or (Pos(',', Value) > 0) or Mentions(BodyText(ASource, ABlock), Field) then
  begin
    Exit;
  end;
  Call := TSetterGenerator.NotifyCall(ASource, AContext.Index, AClass);
  // Die Benachrichtigung ist der Platzhalter; ohne bleibt nur die Endposition.
  if Call <> '' then
  begin
    Call := '${1:' + Call + '}';
  end;
  Text := '';
  Found := False;
  for Line in TSetterGenerator.Statements(Field, Value, Call) do
  begin
    if Found then
    begin
      Text := Text + #10;
    end;
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
    begin
      Continue;
    end;
    Inc(Number);
    Owner := '';
    if OwnerKnown and IsComponentType(ASource, AContext.Index, Field.TypeName) then
    begin
      Owner := '(Self)';
    end;
    Lines := Lines + [Format('%s := ${%d:%s}.Create%s;', [Field.Name, Number,
      TContextSnippets.Escape(FullType(Field)), Owner])];
  end;
  if Number = 0 then
  begin
    Exit;
  end;
  if not Mentions(Body, 'inherited') then
  begin
    Lines := ['inherited;'] + Lines;
  end;
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
  begin
    if not Mentions(Body, Created[Index]) then
    begin
      Lines := Lines + [Format('FreeAndNil(%s);', [Created[Index]])];
    end;
  end;
  if Length(Lines) = 0 then
  begin
    Exit;
  end;
  Result := [Snippet('free', 'free', Format('%d erzeugte Felder von %s freigeben', [Integer(Length(Lines)),
    AClass.Name]), string.Join(#10, Lines) + '$0', nil)];
  if not Mentions(Body, 'inherited') then
  begin
    Result[0].Text := Result[0].Text + #10'inherited;';
  end;
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
  begin
    Exit;
  end;
  Before := TrimLeft(Copy(AContext.LineText, 1, ACharacter));
  for Index := 1 to Length(Before) do
  begin
    if not TTextChars.IsAsciiIdentChar(Before[Index]) then
    begin
      Exit;
    end;
  end;
  Source := TCommandSource.Create(AContext);
  try
    if not Source.ClassAt(ClassSymbol) then
    begin
      Exit;
    end;
    Routine := Source.RoutineAt;
    if Routine = nil then
    begin
      // In der Klassendeklaration.
      if (ClassSymbol.Range.StartPos.Line < AContext.Line) and (ClassSymbol.Range.EndPos.Line > AContext.Line) then
      begin
        Result := PropertyItems(Source, AContext, ClassSymbol);
      end;
      Exit;
    end;
    Block := Routine.FindChild(TSyntaxKind.Block);
    if (Block = nil) or (Block.StartPos.Line >= AContext.Line) or (Block.EndPos.Line <= AContext.Line) then
    begin
      Exit;
    end;
    Dot := LastDelimiter('.', Routine.Name);
    Method := Copy(Routine.Name, Dot + 1, MaxInt);
    Head := LowerCase(TrimLeft(Source.Lines[Routine.StartPos.Line]));
    if StartsStr('constructor ', Head) then
    begin
      Result := ConstructorItems(Source, AContext, ClassSymbol, Block);
    end
    else if StartsStr('destructor ', Head) then
    begin
      Result := DestructorItems(Source, ClassSymbol, Block);
    end
    else if StartsStr('procedure ', Head) then
    begin
      Result := SetterItems(Source, AContext, ClassSymbol, Routine, Block, Method);
    end;
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
  begin
    if CharInSet(C, ['\', '$', '}']) then
    begin
      Result := Result + '\' + C;
    end
    else
    begin
      Result := Result + C;
    end;
  end;
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
            while (AIndex <= Length(AText)) and TTextChars.IsAsciiIdentChar(AText[AIndex]) do
            begin
              Inc(AIndex);
            end;
            Continue;
          end;
          // ${1}, ${1:Vorgabe}, ${1|a,b|}, ${NAME:Vorgabe}
          if AText[AIndex + 1] = '{' then
          begin
            Inc(AIndex, 2);
            while (AIndex <= Length(AText)) and TTextChars.IsAsciiIdentChar(AText[AIndex]) do
            begin
              Inc(AIndex);
            end;
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
              begin
                Inc(AIndex);
              end;
              Result := Result + Copy(AText, Start, AIndex - Start);
              while (AIndex <= Length(AText)) and (AText[AIndex] <> '}') do
              begin
                Inc(AIndex);
              end;
              Inc(AIndex);
            end
            else
            begin
              while (AIndex <= Length(AText)) and (AText[AIndex] <> '}') do
              begin
                Inc(AIndex);
              end;
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
