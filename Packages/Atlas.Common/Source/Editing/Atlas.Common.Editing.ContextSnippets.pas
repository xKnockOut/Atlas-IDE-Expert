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
  Atlas.Text.Chars,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TContextSnippetsText = (PropertyWithSetterWhichChecks, SetOnlyOnChange, CreateObjectFieldsOf, FreeCreatedFieldsOf,
    WithoutNotification, Calls);

const
  cTexts: array[TContextSnippetsText] of TAtlasText = (
    (De: 'Property %s: %s mit Setter %s, der auf Änderung prüft und %s';
     En: 'Property %s: %s with setter %s, which checks for a change and %s'),
    (De: '%s nur bei Änderung setzen; %s'; En: 'Set %s only on change; %s'),
    (De: '%d Objektfelder von %s erzeugen'; En: 'Create %d object fields of %s'),
    (De: '%d erzeugte Felder von %s freigeben'; En: 'Free %d created fields of %s'),
    (De: 'ohne Benachrichtigung'; En: 'without notification'),
    (De: 'ruft %s auf'; En: 'calls %s'));

{$SCOPEDENUMS OFF}

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
  mIndex: Integer;
begin
  Result := '';
  for mIndex := ABlock.StartPos.Line + 1 to ABlock.EndPos.Line - 1 do
  begin
    if mIndex <> ASource.Line then
    begin
      Result := Result + ASource.Lines[mIndex] + #10;
    end;
  end;
end;

/// <summary>Kommt AName als ganzes Wort in AText vor (ohne Groß/Klein)?</summary>
function Mentions(const AText, AName: string): Boolean;
var
  mUpper, mName: string;
  mFound, mAfter: Integer;
begin
  mUpper := UpperCase(AText);
  mName := UpperCase(AName);
  mFound := Pos(mName, mUpper);
  while mFound > 0 do
  begin
    mAfter := mFound + Length(mName);
    if ((mFound = 1) or not TTextChars.IsAsciiIdentChar(mUpper[mFound - 1])) and
      ((mAfter > Length(mUpper)) or not TTextChars.IsAsciiIdentChar(mUpper[mAfter])) then
    begin
      Exit(True);
    end;
    mFound := PosEx(mName, mUpper, mFound + 1);
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
    Result := cTexts[TContextSnippetsText.WithoutNotification].Text;
  end
  else
  begin
    Result := cTexts[TContextSnippetsText.Calls].Fmt([ACall]);
  end;
end;

{ prop }

function PropertyItems(ASource: TCommandSource; const AContext: TSlashContext;
  const AClass: TIndexSymbol): TArray<TContextSnippet>;
var
  mField, mMember: TIndexSymbol;
  mName, mSetter, mTypeText, mCall, mIndent, mLB: string;
  mEdits: TArray<TTextEdit>;
  mEndLine: Integer;
begin
  Result := nil;
  mCall := TSetterGenerator.NotifyCall(ASource, AContext.Index, AClass);
  mLB := ASource.LineBreak;
  mEndLine := AClass.Range.EndPos.Line;
  mIndent := ASource.Indent(mEndLine);
  for mField in Members(ASource, AClass, [TIndexSymbolKind.Field]) do
  begin
    if (Length(mField.Name) < 2) or not CharInSet(mField.Name[1], ['F', 'f']) or (mField.TypeName = '') then
    begin
      Continue;
    end;
    mName := Copy(mField.Name, 2, MaxInt);
    if FindMember(ASource, AClass, mName, [TIndexSymbolKind.Property_], mMember) then
    begin
      Continue;
    end;
    mSetter := 'Set' + mName;
    mTypeText := FullType(mField);
    mEdits := nil;
    if not FindMember(ASource, AClass, mSetter, [TIndexSymbolKind.Method], mMember) then
    begin
      // Wie /changed: eigener private-Abschnitt vor "end", weil Felder vor Methoden stehen müssen.
      mEdits := [ASource.BeforeLine(mEndLine, mIndent + 'private' + mLB + mIndent + '  ' +
        Format('procedure %s(const Value: %s);', [mSetter, mTypeText])),
        ASource.AddBody(AClass.Name, Format('procedure %s.%s(const Value: %s);', [AClass.Name, mSetter, mTypeText]) +
        mLB + TSetterGenerator.Body(mField.Name, 'Value', mCall, mLB))];
    end;
    Result := Result + [Snippet('prop', 'prop ' + mName,
      cTexts[TContextSnippetsText.PropertyWithSetterWhichChecks].Fmt([mName, mTypeText, mSetter,
      NotifyText(mCall)]),
      Format('property ${1:%s}: %s read %s write %s;$0', [TContextSnippets.Escape(mName),
      TContextSnippets.Escape(mTypeText), mField.Name, mSetter]), mEdits)];
  end;
end;

{ changed }

function SetterItems(ASource: TCommandSource; const AContext: TSlashContext; const AClass: TIndexSymbol;
  ARoutine, ABlock: TSyntaxNode; const AMethod: string): TArray<TContextSnippet>;
var
  mProp, mMember: TIndexSymbol;
  mField, mValue, mCall, mText, mLine: string;
  mFound: Boolean;
begin
  Result := nil;
  // Feld: read-Teil der Property, die über AMethod schreibt; sonst FName zu SetName.
  mField := '';
  for mProp in Members(ASource, AClass, [TIndexSymbolKind.Property_]) do
  begin
    if SameText(Accessor(RangeText(ASource.Lines, mProp.Range), 'write'), AMethod) then
    begin
      mField := Accessor(RangeText(ASource.Lines, mProp.Range), 'read');
      Break;
    end;
  end;
  if (mField = '') and StartsText('Set', AMethod) and (Length(AMethod) > 3) then
  begin
    mField := 'F' + Copy(AMethod, 4, MaxInt);
  end;
  if (mField = '') or not FindMember(ASource, AClass, mField, [TIndexSymbolKind.Field], mMember) then
  begin
    Exit;
  end;
  mField := mMember.Name;
  mValue := ParameterNames(RoutineSignature(ASource.Lines[ARoutine.StartPos.Line]));
  if (mValue = '') or (Pos(',', mValue) > 0) or Mentions(BodyText(ASource, ABlock), mField) then
  begin
    Exit;
  end;
  mCall := TSetterGenerator.NotifyCall(ASource, AContext.Index, AClass);
  // Die Benachrichtigung ist der Platzhalter; ohne bleibt nur die Endposition.
  if mCall <> '' then
  begin
    mCall := '${1:' + mCall + '}';
  end;
  mText := '';
  mFound := False;
  for mLine in TSetterGenerator.Statements(mField, mValue, mCall) do
  begin
    if mFound then
    begin
      mText := mText + #10;
    end;
    mText := mText + mLine;
    mFound := True;
  end;
  Result := [Snippet('changed', 'changed ' + mField, cTexts[TContextSnippetsText.SetOnlyOnChange].Fmt([mField,
    NotifyText(TSetterGenerator.NotifyCall(ASource, AContext.Index, AClass))]), mText + '$0', nil)];
end;

{ create }

function ConstructorItems(ASource: TCommandSource; const AContext: TSlashContext; const AClass: TIndexSymbol;
  ABlock: TSyntaxNode): TArray<TContextSnippet>;
var
  mField: TIndexSymbol;
  mCreated: TArray<string>;
  mBody, mText, mOwner: string;
  mLines: TArray<string>;
  mNumber: Integer;
  mOwnerKnown: Boolean;
begin
  Result := nil;
  mBody := BodyText(ASource, ABlock);
  mCreated := CreatedFields(ASource, AClass.Name);
  mOwnerKnown := IsComponentType(ASource, AContext.Index, AClass.Name);
  mLines := nil;
  mNumber := 0;
  for mField in Members(ASource, AClass, [TIndexSymbolKind.Field]) do
  begin
    if (IndexText(mField.Name, mCreated) >= 0) or Mentions(mBody, mField.Name) or
      not IsObjectField(ASource, AContext.Index, mField) then
    begin
      Continue;
    end;
    Inc(mNumber);
    mOwner := '';
    if mOwnerKnown and IsComponentType(ASource, AContext.Index, mField.TypeName) then
    begin
      mOwner := '(Self)';
    end;
    mLines := mLines + [Format('%s := ${%d:%s}.Create%s;', [mField.Name, mNumber,
      TContextSnippets.Escape(FullType(mField)), mOwner])];
  end;
  if mNumber = 0 then
  begin
    Exit;
  end;
  if not Mentions(mBody, 'inherited') then
  begin
    mLines := ['inherited;'] + mLines;
  end;
  mText := string.Join(#10, mLines) + '$0';
  Result := [Snippet('create', 'create', cTexts[TContextSnippetsText.CreateObjectFieldsOf].Fmt([mNumber, AClass.Name]),
    mText,
    nil)];
end;

{ free }

function DestructorItems(ASource: TCommandSource; const AClass: TIndexSymbol;
  ABlock: TSyntaxNode): TArray<TContextSnippet>;
var
  mCreated, mLines: TArray<string>;
  mBody: string;
  mIndex: Integer;
begin
  Result := nil;
  mBody := BodyText(ASource, ABlock);
  mCreated := CreatedFields(ASource, AClass.Name);
  mLines := nil;
  // In umgekehrter Reihenfolge der Erzeugung freigeben, wie /dtor.
  for mIndex := High(mCreated) downto 0 do
  begin
    if not Mentions(mBody, mCreated[mIndex]) then
    begin
      mLines := mLines + [Format('FreeAndNil(%s);', [mCreated[mIndex]])];
    end;
  end;
  if Length(mLines) = 0 then
  begin
    Exit;
  end;
  Result := [Snippet('free', 'free', cTexts[TContextSnippetsText.FreeCreatedFieldsOf].Fmt([Integer(Length(mLines)),
    AClass.Name]), string.Join(#10, mLines) + '$0', nil)];
  if not Mentions(mBody, 'inherited') then
  begin
    Result[0].Text := Result[0].Text + #10'inherited;';
  end;
end;

{ TContextSnippets }

/// <summary>Höchstens ein Wort vor dem Cursor, nichts dahinter.</summary>
function IsWordBeforeCursor(const ALineText: string; ACharacter: Integer): Boolean;
var
  mBefore: string;
  mIndex: Integer;
begin
  Result := (ACharacter >= 0) and (ACharacter <= Length(ALineText)) and
    (Trim(Copy(ALineText, ACharacter + 1, MaxInt)) = '');
  mBefore := TrimLeft(Copy(ALineText, 1, ACharacter));
  mIndex := 1;
  while Result and (mIndex <= Length(mBefore)) do
  begin
    Result := TTextChars.IsAsciiIdentChar(mBefore[mIndex]);
    Inc(mIndex);
  end;
end;

/// <summary>Vorschläge im Rumpf der Methode ARoutine: im Konstruktor, Destruktor bzw. Setter.</summary>
function RoutineItems(ASource: TCommandSource; const AContext: TSlashContext; const AClass: TIndexSymbol;
  ARoutine: TSyntaxNode): TArray<TContextSnippet>;
var
  mBlock: TSyntaxNode;
  mHead, mMethod: string;
begin
  Result := nil;
  mBlock := ARoutine.FindChild(TSyntaxKind.Block);
  if (mBlock = nil) or (mBlock.StartPos.Line >= AContext.Line) or (mBlock.EndPos.Line <= AContext.Line) then
  begin
    Exit;
  end;
  mMethod := Copy(ARoutine.Name, LastDelimiter('.', ARoutine.Name) + 1, MaxInt);
  mHead := LowerCase(TrimLeft(ASource.Lines[ARoutine.StartPos.Line]));
  if StartsStr('constructor ', mHead) then
  begin
    Result := ConstructorItems(ASource, AContext, AClass, mBlock);
  end
  else if StartsStr('destructor ', mHead) then
  begin
    Result := DestructorItems(ASource, AClass, mBlock);
  end
  else if StartsStr('procedure ', mHead) then
  begin
    Result := SetterItems(ASource, AContext, AClass, ARoutine, mBlock, mMethod);
  end;
end;

class function TContextSnippets.At(const AContext: TSlashContext; ACharacter: Integer): TArray<TContextSnippet>;
var
  mSource: TCommandSource;
  mClass: TIndexSymbol;
  mRoutine: TSyntaxNode;
begin
  Result := nil;
  if not IsWordBeforeCursor(AContext.LineText, ACharacter) then
  begin
    Exit;
  end;
  mSource := TCommandSource.Create(AContext);
  try
    if not mSource.ClassAt(mClass) then
    begin
      Exit;
    end;
    mRoutine := mSource.RoutineAt;
    if mRoutine <> nil then
    begin
      Result := RoutineItems(mSource, AContext, mClass, mRoutine);
    end
    // In der Klassendeklaration.
    else if (mClass.Range.StartPos.Line < AContext.Line) and (mClass.Range.EndPos.Line > AContext.Line) then
    begin
      Result := PropertyItems(mSource, AContext, mClass);
    end;
  finally
    mSource.Free;
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

function PlainUntilClose(const AText: string; var AIndex: Integer; AInside: Boolean): string; forward;

/// <summary>Zeichen hinter "\" an AIndex: geschützte Zeichen ohne "\", sonst "\" selbst.</summary>
function EscapedChar(const AText: string; var AIndex: Integer): string;
begin
  if (AIndex < Length(AText)) and CharInSet(AText[AIndex + 1], ['\', '$', '}', ',', '|']) then
  begin
    Result := AText[AIndex + 1];
    Inc(AIndex, 2);
  end
  else
  begin
    Result := '\';
    Inc(AIndex);
  end;
end;

procedure SkipIdent(const AText: string; var AIndex: Integer);
begin
  while (AIndex <= Length(AText)) and TTextChars.IsAsciiIdentChar(AText[AIndex]) do
  begin
    Inc(AIndex);
  end;
end;

/// <summary>Bis hinter das nächste "}".</summary>
procedure SkipPastClose(const AText: string; var AIndex: Integer);
begin
  while (AIndex <= Length(AText)) and (AText[AIndex] <> '}') do
  begin
    Inc(AIndex);
  end;
  Inc(AIndex);
end;

/// <summary>Auswahl: die erste Möglichkeit bis "," bzw. "|".</summary>
function FirstChoice(const AText: string; var AIndex: Integer): string;
var
  mStart: Integer;
begin
  mStart := AIndex;
  while (AIndex <= Length(AText)) and not CharInSet(AText[AIndex], [',', '|']) do
  begin
    Inc(AIndex);
  end;
  Result := Copy(AText, mStart, AIndex - mStart);
end;

/// <summary>${1}, ${1:Vorgabe}, ${1|a,b|}, ${NAME:Vorgabe} ab dem Namen: Vorgabe bzw. erste Auswahl.</summary>
function PlaceholderText(const AText: string; var AIndex: Integer): string;
begin
  Result := '';
  SkipIdent(AText, AIndex);
  if (AIndex <= Length(AText)) and (AText[AIndex] = ':') then
  begin
    Inc(AIndex);
    Result := PlainUntilClose(AText, AIndex, True);
  end
  else if (AIndex <= Length(AText)) and (AText[AIndex] = '|') then
  begin
    Inc(AIndex);
    Result := FirstChoice(AText, AIndex);
    SkipPastClose(AText, AIndex);
  end
  else
  begin
    SkipPastClose(AText, AIndex);
  end;
end;

/// <summary>Platzhalter ab "$" an AIndex lesen; False, wenn das "$" Text bleibt ($FF, Textende).</summary>
function DollarText(const AText: string; var AIndex: Integer; out APart: string): Boolean;
begin
  APart := '';
  Result := AIndex < Length(AText);
  if not Result then
  begin
    Exit;
  end;
  if CharInSet(AText[AIndex + 1], ['0'..'9']) then
  begin
    // $1; "$" vor einem Buchstaben bleibt Text ($FF).
    Inc(AIndex);
    SkipIdent(AText, AIndex);
  end
  else if AText[AIndex + 1] = '{' then
  begin
    Inc(AIndex, 2);
    APart := PlaceholderText(AText, AIndex);
  end
  else
  begin
    Result := False;
  end;
end;

/// <summary>Liest ab AIndex bis zum passenden "}" (oder Textende) und gibt den Klartext zurück; AIndex steht danach
/// hinter dem "}".</summary>
function PlainUntilClose(const AText: string; var AIndex: Integer; AInside: Boolean): string;
var
  mPart: string;
begin
  Result := '';
  while AIndex <= Length(AText) do
  begin
    case AText[AIndex] of
      '\':
        begin
          Result := Result + EscapedChar(AText, AIndex);
          Continue;
        end;
      '}':
        if AInside then
        begin
          Inc(AIndex);
          Exit;
        end;
      '$':
        if DollarText(AText, AIndex, mPart) then
        begin
          Result := Result + mPart;
          Continue;
        end;
    end;
    Result := Result + AText[AIndex];
    Inc(AIndex);
  end;
end;

class function TContextSnippets.ToPlain(const ASnippet: string): string;
var
  mIndex: Integer;
begin
  mIndex := 1;
  Result := PlainUntilClose(ASnippet, mIndex, False);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Editing.ContextSnippets', cTexts);

end.
