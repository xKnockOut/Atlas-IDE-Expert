unit Atlas.Core.Completion.Snippets;

// Code-Vorlagen (#51): Format der Dateien *.atlas-snippet, mitgelieferte
// Vorlagen und das Einsetzen mit Platzhaltern, ohne Editor.
//
// Dateiformat: Kopfzeilen "Schlüssel: Wert" (name, prefix, description), dann
// eine Zeile "---" und der Text der Vorlage. Zeilen mit "#" im Kopf sind
// Kommentare. Postfix-Vorlagen (#188) haben dazu "postfix: true" und optional
// "type: …" (Merkmal wie class, string, boolean, enumerable, reference,
// constructor, function, any oder ein Typname); im Text steht $expr für den
// Ausdruck vor dem Punkt. Sie erscheinen nicht am Anweisungsanfang, sondern
// gehen an den Server, der sie hinter passenden Ausdrücken anbietet. Platzhalter im Text:
//   ${1:List}  Platzhalter 1 mit Vorgabetext
//   ${2}       Platzhalter 2 ohne Vorgabe
//   $0, ${0}   Cursor nach dem letzten Platzhalter
// Wiederholte Nummern sind verknüpft und zeigen denselben Text. Ein "$" vor
// etwas anderem bleibt stehen, auch "$0F" oder "$FF": Hexzahlen im Delphi-Code
// sind keine Platzhalter. "$$" steht für ein einzelnes "$" (für Text wie
// "$1;", der sonst wie ein Platzhalter aussähe; so übernimmt Atlas die Live
// Templates der IDE).
// Optional "context: …" (#719, Kontext aus #665): wo die Vorlage im
// Erzeugen-Menü erscheint, kommagetrennt: statement (in einer Routine),
// declaration (Typ- und Klassenebene), any (überall, wie ohne Angabe) oder
// die Orte des Servers routine, class, record, interfaceType, interface,
// implementation, program. Die Vervollständigung beachtet ihn nicht.
// Optional "file: unit|form|test" (#759): Dateivorlage für „Neu mit Atlas“
// auf der Willkommensseite (Unit, Formular, Testklasse). Der Text ist dann
// die ganze neue Datei; %Unit% steht für den Namen der Unit, %Form% für den
// des Formulars, %Ancestor% für die Basisklasse des Formulars ohne T und
// %Name% für den Namen der Unit ohne Namespace. Dateivorlagen erscheinen
// weder in der Vervollständigung noch im normalen Erzeugen-Menü.

interface

uses
  System.SysUtils,
  System.JSON;

{$SCOPEDENUMS ON}

type
  /// <summary>Herkunft; bei gleichem Kürzel gilt User vor Ide vor BuiltIn.</summary>
  TAtlasSnippetOrigin = (BuiltIn, Ide, User);

  TAtlasSnippet = record
    /// <summary>Anzeigename, z. B. „try…finally mit Create/Free“; '' = Prefix.</summary>
    Name: string;
    /// <summary>Kürzel, nach dem die Liste filtert, z. B. "tryf".</summary>
    Prefix: string;
    Description: string;
    /// <summary>Text mit Platzhaltern, Zeilen mit #10.</summary>
    Body: string;
    Origin: TAtlasSnippetOrigin;
    /// <summary>Datei einer eigenen Vorlage; '' bei mitgelieferten.</summary>
    FileName: string;
    /// <summary>Postfix-Vorlage (#188): Kürzel hinter "Ausdruck."; $expr im Text steht für den Ausdruck.</summary>
    Postfix: Boolean;
    /// <summary>Bedingung einer Postfix-Vorlage: Merkmal oder Typname; '' = jeder Ausdruck.</summary>
    TypeCondition: string;
    /// <summary>Kontext im Erzeugen-Menü (#719): statement, declaration, any oder Orte des Servers, kommagetrennt;
    /// '' = überall.</summary>
    Context: string;
    /// <summary>Dateivorlage (#759): "unit", "form" oder "test"; '' = Code-Vorlage.</summary>
    FileKind: string;
  end;

  TAtlasSnippetList = TArray<TAtlasSnippet>;

  /// <summary>Platzhalter im eingesetzten Text.</summary>
  TAtlasSnippetStop = record
    /// <summary>0 = Endposition.</summary>
    Number: Integer;
    /// <summary>0-basiert, UTF-16-Einheiten ab dem Anfang des eingesetzten Texts.</summary>
    Start: Integer;
    Length: Integer;
  end;

  TAtlasSnippetExpansion = record
    Text: string;
    /// <summary>In Textreihenfolge.</summary>
    Stops: TArray<TAtlasSnippetStop>;
    /// <summary>Gibt es Platzhalter mit Nummer ab 1?</summary>
    function HasPlaceholders: Boolean;
  end;

  TAtlasSnippets = class
  public const
    FileExtension = '.atlas-snippet';
  public
    /// <summary>Liest eine Vorlagendatei. False mit AError, wenn Kopf oder Text fehlen oder ein Schlüssel
    /// unbekannt ist.</summary>
    class function Parse(const AText, AFileName: string; out ASnippet: TAtlasSnippet;
      out AError: string): Boolean; static;
    /// <summary>Dateiinhalt im Format von Parse (Zeilen mit #10); für die Seite „Snippets“.</summary>
    class function ToFileText(const ASnippet: TAtlasSnippet): string; static;
    /// <summary>Dateiname zum Kürzel, z. B. "tryf.atlas-snippet"; andere Zeichen als Buchstaben, Ziffern und _
    /// werden zu _.</summary>
    class function FileNameFor(const APrefix: string): string; static;
    /// <summary>tryf, trye, forin, fori, while, repeat, class, record, prop, propset, comp, reg (je mit Kontext).
    /// </summary>
    class function BuiltIn: TAtlasSnippetList; static;
    /// <summary>Vorlagen aus AUser ersetzen die aus ABuiltIn mit gleichem Kürzel (ohne Groß/Klein). Für
    /// mitgelieferte, IDE- und eigene Vorlagen zweimal: Merge(Merge(BuiltIn, Ide), User).</summary>
    class function Merge(const ABuiltIn, AUser: TAtlasSnippetList): TAtlasSnippetList; static;
    /// <summary>Setzt ABody ein: jede Zeile nach der ersten bekommt AIndent vorangestellt, Zeilenumbrüche werden
    /// zu ALineBreak, Platzhalter zu ihrem Vorgabetext (verknüpfte zum ersten vorhandenen).</summary>
    class function Expand(const ABody, AIndent, ALineBreak: string): TAtlasSnippetExpansion; static;
    /// <summary>Klartext ohne Platzhalter, Zeilen mit #10; für Vorschau und Detailpanel.</summary>
    class function PlainText(const ABody: string): string; static;
    /// <summary>Snippet des Servers (LSP-Syntax, insertTextFormat 2) im eigenen Format: \$ wird zu $$, $1 zu ${1},
    /// Auswahl ${1|a,b|} zu ${1:a}; verschachtelte Platzhalter und ${NAME:…} werden zu ihrem Vorgabetext, "$" vor
    /// einem Buchstaben bleibt Text.</summary>
    class function FromLsp(const AText: string): string; static;
    /// <summary>Einrückung am Anfang von ALine (Leerzeichen und Tabs).</summary>
    class function IndentOf(const ALine: string): string; static;
    /// <summary>Stand des Ordners (Namen, Größen, Zeitstempel der Vorlagendateien); ändert sich, sobald eine
    /// Datei dazukommt, wegfällt oder gespeichert wird. '' ohne Ordner.</summary>
    class function FolderStamp(const APath: string): string; static;
    /// <summary>Alle *.atlas-snippet in APath; Fehler je Datei in AErrors ("Datei: Meldung").</summary>
    class function LoadFolder(const APath: string; out AErrors: TArray<string>): TAtlasSnippetList; static;
    /// <summary>Nur die Postfix-Vorlagen (#188) bzw. alle anderen.</summary>
    class function Postfixes(const AList: TAtlasSnippetList): TAtlasSnippetList; static;
    class function WithoutPostfix(const AList: TAtlasSnippetList): TAtlasSnippetList; static;
    /// <summary>Parameter für atlas/postfixTemplates: {"templates": [{"key", "description", "body", "type"}]}.
    /// Gehört dem Aufrufer.</summary>
    class function PostfixParams(const AList: TAtlasSnippetList): TJSONObject; static;
    /// <summary>Erlaubte Wörter für "context:" (#719).</summary>
    class function ContextWords: TArray<string>; static;
    /// <summary>Erlaubte Werte für "file:" (#759): unit, form, test.</summary>
    class function FileKinds: TArray<string>; static;
    /// <summary>Nur die Dateivorlagen (#759) bzw. alle anderen.</summary>
    class function FileTemplates(const AList: TAtlasSnippetList): TAtlasSnippetList; static;
    class function WithoutFileTemplates(const AList: TAtlasSnippetList): TAtlasSnippetList; static;
    /// <summary>Passt der Kontext AContext zu den Orten APlaces des Servers (routine, class, …)? '' und any immer;
    /// statement = routine; declaration = class, record, interfaceType, interface, implementation, program
    /// außerhalb einer Routine.</summary>
    class function FitsContext(const AContext: string; const APlaces: TArray<string>): Boolean; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.Classes,
  System.StrUtils,
  Atlas.Text.Lines,
  Atlas.Text.Chars,
  Atlas.Core.Localization.Language;

{$SCOPEDENUMS ON}

type
  /// <summary>Benutzertexte dieser Unit (#1458).</summary>
  TSnippetsText = (LineUnknownContextAllowed, LinePostfixIsTrueOr, LineUnknownFileKindAllowed,
    LineUnknownKeyAllowedName, LineKeyValueOrExpected, LineBetweenHeaderAndText, KeyPrefixIsMissing,
    PrefixOnlyLettersDigitsAnd, SnippetTextIsMissing, TryFinallyWithCreateFree, CreateAnObjectAndFree,
    HandleAnExceptionOfA, ForInLoop, IterateOverTheItemsOf, ForLoopWithCounter, CountFrom0ToCount, WhileLoop,
    AsLongAsTheCondition, RepeatUntilLoop, AtLeastOnceUntilThe, ClassWithConstructorAndDestructor,
    ClassDeclarationInTheType, RecordDeclarationInTheType, PropertyWithFieldAndSetter, DeclarationInTheClassPropset,
    SetterWithChangeCheck, SetsTheFieldOnlyWhen, ComponentSkeleton, ComponentWithPublishedSectionReg,
    RegisterProcedure, RegisterTheComponentInThe);

const
  cTexts: array[TAtlasLanguage, TSnippetsText] of string = (
    ('Zeile %d: unbekannter Kontext "%s" (erlaubt: %s)',
     'Zeile %d: "postfix" ist true oder false',
     'Zeile %d: unbekannte Dateiart "%s" (erlaubt: %s)',
     'Zeile %d: unbekannter Schlüssel "%s" (erlaubt: name, prefix, description, postfix, type, context, file)',
     'Zeile %d: "Schlüssel: Wert" oder "---" erwartet',
     'Zeile "---" zwischen Kopf und Text fehlt',
     'Schlüssel "prefix" fehlt',
     'Kürzel "%s": nur Buchstaben, Ziffern und _',
     'Text der Vorlage fehlt',
     'try…finally mit Create/Free',
     'Objekt anlegen und sicher wieder freigeben.',
     'Ausnahme einer Klasse behandeln.',
     'for…in-Schleife',
     'Über die Elemente einer Liste laufen (Inline-Variable).',
     'for-Schleife mit Zähler',
     'Von 0 bis Count - 1 zählen (Inline-Variable).',
     'while-Schleife',
     'Solange die Bedingung gilt.',
     'repeat…until-Schleife',
     'Mindestens einmal, bis die Bedingung gilt.',
     'Klasse mit Konstruktor und Destruktor',
     'Klassendeklaration im type-Abschnitt.',
     'Record-Deklaration im type-Abschnitt.',
     'Property mit Feld und Setter',
     'Deklaration in der Klasse; den Setter legt propset an.',
     'Setter mit Prüfung auf Änderung',
     'Setzt das Feld nur bei Änderung und zeichnet neu.',
     'Komponentengerüst',
     'Komponente mit published-Abschnitt; die Registrierung legt reg an.',
     'Register-Prozedur',
     'Komponente in der Palette registrieren.'),
    ('Line %d: unknown context "%s" (allowed: %s)',
     'Line %d: "postfix" is true or false',
     'Line %d: unknown file kind "%s" (allowed: %s)',
     'Line %d: unknown key "%s" (allowed: name, prefix, description, postfix, type, context, file)',
     'Line %d: "key: value" or "---" expected',
     'Line "---" between header and text is missing',
     'Key "prefix" is missing',
     'Prefix "%s": only letters, digits and _',
     'Snippet text is missing',
     'try…finally with Create/Free',
     'Create an object and free it safely.',
     'Handle an exception of a class.',
     'for…in loop',
     'Iterate over the items of a list (inline variable).',
     'for loop with counter',
     'Count from 0 to Count - 1 (inline variable).',
     'while loop',
     'As long as the condition holds.',
     'repeat…until loop',
     'At least once, until the condition holds.',
     'Class with constructor and destructor',
     'Class declaration in the type section.',
     'Record declaration in the type section.',
     'Property with field and setter',
     'Declaration in the class; propset creates the setter.',
     'Setter with change check',
     'Sets the field only when it changes and repaints.',
     'Component skeleton',
     'Component with published section; reg creates the registration.',
     'Register procedure',
     'Register the component in the palette.'));

/// <summary>Text AId in der Sprache der Oberfläche.</summary>
function UiText(AId: TSnippetsText): string;
begin
  Result := cTexts[TAtlasTextLanguage.Current, AId];
end;

type
  TSegment = record
    IsStop: Boolean;
    Number: Integer;
    HasDefault: Boolean;
    Text: string;
  end;

function IsDigit(AC: Char): Boolean;
begin
  Result := (AC >= '0') and (AC <= '9');
end;

function NormalizeBreaks(const AText: string): string;
begin
  Result := StringReplace(StringReplace(AText, #13#10, #10, [rfReplaceAll]), #13, #10, [rfReplaceAll]);
end;

procedure FlushLiteral(var ASegments: TArray<TSegment>; var ALiteral: string);
var
  mSegment: TSegment;
begin
  if ALiteral = '' then
  begin
    Exit;
  end;
  mSegment := Default(TSegment);
  mSegment.Text := ALiteral;
  ASegments := ASegments + [mSegment];
  ALiteral := '';
end;

/// <summary>${n} bzw. ${n:Vorgabe} ab dem "$" an AIndex; ANext: Index hinter "}".</summary>
function TryBracedStop(const ABody: string; AIndex: Integer; out ASegment: TSegment; out ANext: Integer): Boolean;
var
  mClose, mColon, mNumber: Integer;
  mInner: string;
begin
  ASegment := Default(TSegment);
  ANext := AIndex;
  if not ((AIndex + 2 <= Length(ABody)) and (ABody[AIndex + 1] = '{') and IsDigit(ABody[AIndex + 2])) then
  begin
    Exit(False);
  end;
  mClose := AIndex + 2;
  while (mClose <= Length(ABody)) and (ABody[mClose] <> '}') and (ABody[mClose] <> #10) do
  begin
    Inc(mClose);
  end;
  mInner := Copy(ABody, AIndex + 2, mClose - AIndex - 2);
  mColon := Pos(':', mInner);
  if mColon = 0 then
  begin
    mColon := Length(mInner) + 1;
  end;
  Result := (mClose <= Length(ABody)) and (ABody[mClose] = '}') and
    TryStrToInt(Copy(mInner, 1, mColon - 1), mNumber) and (mNumber >= 0);
  if Result then
  begin
    ASegment.IsStop := True;
    ASegment.Number := mNumber;
    ASegment.HasDefault := mColon <= Length(mInner);
    ASegment.Text := Copy(mInner, mColon + 1, MaxInt);
    ANext := mClose + 1;
  end;
end;

/// <summary>$0 allein, nicht $0F, ab dem "$" an AIndex.</summary>
function TryEndStop(const ABody: string; AIndex: Integer; out ASegment: TSegment; out ANext: Integer): Boolean;
begin
  ASegment := Default(TSegment);
  ANext := AIndex + 2;
  Result := (AIndex < Length(ABody)) and (ABody[AIndex + 1] = '0') and
    ((AIndex + 2 > Length(ABody)) or not TTextChars.IsAsciiIdentChar(ABody[AIndex + 2]));
  ASegment.IsStop := Result;
end;

/// <summary>Zerlegt den Text in Klartext und Platzhalter.</summary>
function Segments(const ABody: string): TArray<TSegment>;
var
  mIndex, mNext: Integer;
  mLiteral: string;
  mSegment: TSegment;
begin
  Result := nil;
  mLiteral := '';
  mIndex := 1;
  while mIndex <= Length(ABody) do
  begin
    if ABody[mIndex] <> '$' then
    begin
      mLiteral := mLiteral + ABody[mIndex];
      Inc(mIndex);
    end
    // "$$" = "$"
    else if (mIndex < Length(ABody)) and (ABody[mIndex + 1] = '$') then
    begin
      mLiteral := mLiteral + '$';
      Inc(mIndex, 2);
    end
    else if TryBracedStop(ABody, mIndex, mSegment, mNext) or TryEndStop(ABody, mIndex, mSegment, mNext) then
    begin
      FlushLiteral(Result, mLiteral);
      Result := Result + [mSegment];
      mIndex := mNext;
    end
    else
    begin
      mLiteral := mLiteral + '$';
      Inc(mIndex);
    end;
  end;
  FlushLiteral(Result, mLiteral);
end;

/// <summary>Wörter von "context:" prüfen (#719); False mit AError bei einem unbekannten.</summary>
function CheckContext(const AValue: string; ALine: Integer; out AError: string): Boolean;
var
  mWord: string;
begin
  AError := '';
  for mWord in AValue.Split([',']) do
  begin
    if (Trim(mWord) <> '') and (IndexText(Trim(mWord), TAtlasSnippets.ContextWords) < 0) then
    begin
      AError := Format(UiText(TSnippetsText.LineUnknownContextAllowed),
        [ALine, Trim(mWord), string.Join(', ', TAtlasSnippets.ContextWords)]);
      Exit(False);
    end;
  end;
  Result := True;
end;

function ApplyPostfix(var ASnippet: TAtlasSnippet; const AValue: string; ALine: Integer;
  out AError: string): Boolean;
begin
  AError := '';
  Result := SameText(AValue, 'true') or SameText(AValue, 'false');
  if Result then
  begin
    ASnippet.Postfix := ASnippet.Postfix or SameText(AValue, 'true');
  end
  else
  begin
    AError := Format(UiText(TSnippetsText.LinePostfixIsTrueOr), [ALine]);
  end;
end;

function ApplyFileKind(var ASnippet: TAtlasSnippet; const AValue: string; ALine: Integer;
  out AError: string): Boolean;
begin
  AError := '';
  Result := IndexText(AValue, TAtlasSnippets.FileKinds) >= 0;
  if Result then
  begin
    ASnippet.FileKind := LowerCase(AValue);
  end
  else
  begin
    AError := Format(UiText(TSnippetsText.LineUnknownFileKindAllowed),
      [ALine, AValue, string.Join(', ', TAtlasSnippets.FileKinds)]);
  end;
end;

/// <summary>Schlüssel AKey der Kopfzeile ALine übernehmen; False mit AError bei einem Fehler.</summary>
function ApplyKey(var ASnippet: TAtlasSnippet; const AKey, AValue: string; ALine: Integer;
  out AError: string): Boolean;
begin
  AError := '';
  Result := True;
  if AKey = 'name' then
  begin
    ASnippet.Name := AValue;
  end
  else if AKey = 'prefix' then
  begin
    ASnippet.Prefix := AValue;
  end
  else if AKey = 'description' then
  begin
    ASnippet.Description := AValue;
  end
  else if AKey = 'postfix' then
  begin
    Result := ApplyPostfix(ASnippet, AValue, ALine, AError);
  end
  else if AKey = 'type' then
  begin
    ASnippet.TypeCondition := AValue;
  end
  else if AKey = 'context' then
  begin
    Result := CheckContext(AValue, ALine, AError);
    if Result then
    begin
      ASnippet.Context := AValue;
    end;
  end
  else if AKey = 'file' then
  begin
    Result := ApplyFileKind(ASnippet, AValue, ALine, AError);
  end
  else
  begin
    AError := Format(UiText(TSnippetsText.LineUnknownKeyAllowedName), [ALine, AKey]);
    Result := False;
  end;
end;

/// <summary>Kopfzeilen bis "---" lesen; ASeparator: Index dieser Zeile, -1 ohne. False mit AError bei einem
/// Fehler.</summary>
function ReadHeader(const ALines: TArray<string>; var ASnippet: TAtlasSnippet; out ASeparator: Integer;
  out AError: string): Boolean;
var
  mIndex, mColon: Integer;
  mLine: string;
begin
  ASeparator := -1;
  AError := '';
  Result := True;
  mIndex := 0;
  while Result and (mIndex <= High(ALines)) do
  begin
    mLine := Trim(ALines[mIndex]);
    if mLine = '---' then
    begin
      ASeparator := mIndex;
      Break;
    end;
    mColon := Pos(':', mLine);
    if (mLine <> '') and (mLine[1] <> '#') and (mColon = 0) then
    begin
      AError := Format(UiText(TSnippetsText.LineKeyValueOrExpected), [mIndex + 1]);
      Result := False;
    end
    else if (mLine <> '') and (mLine[1] <> '#') then
    begin
      Result := ApplyKey(ASnippet, LowerCase(Trim(Copy(mLine, 1, mColon - 1))), Trim(Copy(mLine, mColon + 1, MaxInt)),
        mIndex + 1, AError);
    end;
    Inc(mIndex);
  end;
end;

/// <summary>Trenner und Kürzel prüfen: "---" vorhanden, Kürzel gesetzt und nur aus Buchstaben, Ziffern und _.
/// </summary>
function CheckHead(ASeparator: Integer; const APrefix: string; out AError: string): Boolean;
var
  mIndex: Integer;
begin
  AError := '';
  if ASeparator < 0 then
  begin
    AError := UiText(TSnippetsText.LineBetweenHeaderAndText);
  end
  else if APrefix = '' then
  begin
    AError := UiText(TSnippetsText.KeyPrefixIsMissing);
  end;
  for mIndex := 1 to Length(APrefix) do
  begin
    if (AError = '') and not TTextChars.IsAsciiIdentChar(APrefix[mIndex]) then
    begin
      AError := Format(UiText(TSnippetsText.PrefixOnlyLettersDigitsAnd), [APrefix]);
    end;
  end;
  Result := AError = '';
end;

/// <summary>Text nach "---", ohne Leerzeilen und Leerzeichen am Ende.</summary>
function BodyOf(const ALines: TArray<string>; ASeparator: Integer): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := ASeparator + 1 to High(ALines) do
  begin
    if mIndex > ASeparator + 1 then
    begin
      Result := Result + #10;
    end;
    Result := Result + ALines[mIndex];
  end;
  // Leerzeilen am Ende gehören nicht zur Vorlage.
  while (Result <> '') and ((Result[Length(Result)] = #10) or (Result[Length(Result)] = ' ')) do
  begin
    Delete(Result, Length(Result), 1);
  end;
end;

/// <summary>Ein Wort von "context:" passt zu den Orten APlaces (siehe TAtlasSnippets.FitsContext).</summary>
function WordFits(const AWord: string; const APlaces: TArray<string>; AInRoutine: Boolean): Boolean;
var
  mPlace: string;
begin
  if SameText(AWord, 'any') or (SameText(AWord, 'statement') and AInRoutine) then
  begin
    Exit(True);
  end;
  for mPlace in APlaces do
  begin
    // Deklarationen: Typ- und Klassenebene, nicht im Rumpf einer Methode.
    if SameText(AWord, mPlace) or (SameText(AWord, 'declaration') and not AInRoutine and
      not SameText(mPlace, 'routine')) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function ListHasPrefix(const AList: TAtlasSnippetList; const APrefix: string): Boolean;
var
  mItem: TAtlasSnippet;
begin
  Result := False;
  for mItem in AList do
  begin
    if SameText(mItem.Prefix, APrefix) then
    begin
      Exit(True);
    end;
  end;
end;

function HasSameOrigin(const AList: TAtlasSnippetList; const ASnippet: TAtlasSnippet): Boolean;
var
  mItem: TAtlasSnippet;
begin
  Result := False;
  for mItem in AList do
  begin
    if (mItem.Origin = ASnippet.Origin) and SameText(mItem.Prefix, ASnippet.Prefix) then
    begin
      Exit(True);
    end;
  end;
end;

procedure AddSnippetFiles(const APath: string; ANames: TStringList);
var
  mSearch: TSearchRec;
begin
  if FindFirst(IncludeTrailingPathDelimiter(APath) + '*' + TAtlasSnippets.FileExtension, faAnyFile, mSearch) <> 0 then
  begin
    Exit;
  end;
  try
    repeat
      if (mSearch.Attr and faDirectory) = 0 then
      begin
        ANames.Add(mSearch.Name);
      end;
    until FindNext(mSearch) <> 0;
  finally
    FindClose(mSearch);
  end;
end;

/// <summary>Namen der Vorlagendateien in APath, sortiert: Bei doppelten Kürzeln gilt immer dieselbe Datei.
/// </summary>
function SnippetFileNames(const APath: string): TArray<string>;
var
  mNames: TStringList;
  mIndex: Integer;
begin
  mNames := TStringList.Create;
  try
    AddSnippetFiles(APath, mNames);
    mNames.Sort;
    SetLength(Result, mNames.Count);
    for mIndex := 0 to mNames.Count - 1 do
    begin
      Result[mIndex] := mNames[mIndex];
    end;
  finally
    mNames.Free;
  end;
end;

/// <summary>Eine Vorlagendatei lesen: an AList anhängen, sonst Fehler "Datei: Meldung" an AErrors.</summary>
procedure LoadSnippetFile(const APath, AName: string; var AList: TAtlasSnippetList; var AErrors: TArray<string>);
var
  mLines: TStringList;
  mItem: TAtlasSnippet;
  mError: string;
begin
  mLines := TStringList.Create;
  try
    try
      mLines.LoadFromFile(IncludeTrailingPathDelimiter(APath) + AName, TEncoding.UTF8);
      if TAtlasSnippets.Parse(mLines.Text, IncludeTrailingPathDelimiter(APath) + AName, mItem, mError) then
      begin
        AList := AList + [mItem];
      end
      else
      begin
        AErrors := AErrors + [AName + ': ' + mError];
      end;
    except
      on E: Exception do
        AErrors := AErrors + [AName + ': ' + E.Message];
    end;
  finally
    mLines.Free;
  end;
end;

{ TAtlasSnippetExpansion }

function TAtlasSnippetExpansion.HasPlaceholders: Boolean;
var
  mStop: TAtlasSnippetStop;
begin
  Result := False;
  for mStop in Stops do
  begin
    if mStop.Number > 0 then
    begin
      Exit(True);
    end;
  end;
end;

{ TAtlasSnippets }

class function TAtlasSnippets.Parse(const AText, AFileName: string; out ASnippet: TAtlasSnippet;
  out AError: string): Boolean;
var
  mLines: TArray<string>;
  mSeparator: Integer;
  mBody: string;
begin
  ASnippet := Default(TAtlasSnippet);
  ASnippet.Origin := TAtlasSnippetOrigin.User;
  ASnippet.FileName := AFileName;
  mLines := NormalizeBreaks(AText).Split([#10]);
  Result := ReadHeader(mLines, ASnippet, mSeparator, AError) and CheckHead(mSeparator, ASnippet.Prefix, AError);
  if not Result then
  begin
    Exit;
  end;
  mBody := BodyOf(mLines, mSeparator);
  Result := Trim(mBody) <> '';
  if not Result then
  begin
    AError := UiText(TSnippetsText.SnippetTextIsMissing);
    Exit;
  end;
  ASnippet.Body := mBody;
  if ASnippet.Name = '' then
  begin
    ASnippet.Name := ASnippet.Prefix;
  end;
end;

class function TAtlasSnippets.ToFileText(const ASnippet: TAtlasSnippet): string;

  function OneLine(const AText: string): string;
  begin
    Result := Trim(StringReplace(NormalizeBreaks(AText), #10, ' ', [rfReplaceAll]));
  end;

begin
  Result := 'name: ' + OneLine(ASnippet.Name) + #10 + 'prefix: ' + OneLine(ASnippet.Prefix) + #10 +
    'description: ' + OneLine(ASnippet.Description) + #10;
  if ASnippet.Postfix then
  begin
    Result := Result + 'postfix: true' + #10;
    if ASnippet.TypeCondition <> '' then
    begin
      Result := Result + 'type: ' + OneLine(ASnippet.TypeCondition) + #10;
    end;
  end;
  if ASnippet.Context <> '' then
  begin
    Result := Result + 'context: ' + OneLine(ASnippet.Context) + #10;
  end;
  if ASnippet.FileKind <> '' then
  begin
    Result := Result + 'file: ' + OneLine(ASnippet.FileKind) + #10;
  end;
  Result := Result + '---' + #10 + NormalizeBreaks(ASnippet.Body) + #10;
end;

class function TAtlasSnippets.FileNameFor(const APrefix: string): string;
var
  mIndex: Integer;
begin
  Result := APrefix;
  for mIndex := 1 to Length(Result) do
  begin
    if not TTextChars.IsAsciiIdentChar(Result[mIndex]) then
    begin
      Result[mIndex] := '_';
    end;
  end;
  Result := Result + FileExtension;
end;

function Snippet(const APrefix, AName, ADescription, ABody, AContext: string): TAtlasSnippet;
begin
  Result := Default(TAtlasSnippet);
  Result.Prefix := APrefix;
  Result.Name := AName;
  Result.Description := ADescription;
  Result.Body := ABody;
  Result.Origin := TAtlasSnippetOrigin.BuiltIn;
  Result.Context := AContext;
end;

class function TAtlasSnippets.BuiltIn: TAtlasSnippetList;
begin
  Result := [
    Snippet('tryf', UiText(TSnippetsText.TryFinallyWithCreateFree), UiText(TSnippetsText.CreateAnObjectAndFree),
      '${1:List} := ${2:TStringList}.Create;'#10'try'#10'  $0'#10'finally'#10'  ${1}.Free;'#10'end;', 'statement'),
    Snippet('trye', 'try…except', UiText(TSnippetsText.HandleAnExceptionOfA),
      'try'#10'  $0'#10'except'#10'  on E: ${1:Exception} do'#10'    ${2:raise};'#10'end;', 'statement'),
    Snippet('forin', UiText(TSnippetsText.ForInLoop), UiText(TSnippetsText.IterateOverTheItemsOf),
      'for var ${1:Item} in ${2:List} do'#10'begin'#10'  $0'#10'end;', 'statement'),
    Snippet('fori', UiText(TSnippetsText.ForLoopWithCounter), UiText(TSnippetsText.CountFrom0ToCount),
      'for var ${1:I} := ${2:0} to ${3:List.Count - 1} do'#10'begin'#10'  $0'#10'end;', 'statement'),
    Snippet('while', UiText(TSnippetsText.WhileLoop), UiText(TSnippetsText.AsLongAsTheCondition),
      'while ${1:Condition} do'#10'begin'#10'  $0'#10'end;', 'statement'),
    Snippet('repeat', UiText(TSnippetsText.RepeatUntilLoop), UiText(TSnippetsText.AtLeastOnceUntilThe),
      'repeat'#10'  $0'#10'until ${1:Condition};', 'statement'),
    Snippet('class', UiText(TSnippetsText.ClassWithConstructorAndDestructor),
      UiText(TSnippetsText.ClassDeclarationInTheType),
      '${1:TMyClass} = class(${2:TObject})'#10'private'#10'  $0'#10'public'#10'  constructor Create;'#10 +
      '  destructor Destroy; override;'#10'end;', 'declaration'),
    Snippet('record', 'Record', UiText(TSnippetsText.RecordDeclarationInTheType),
      '${1:TMyRecord} = record'#10'  ${2:Value}: ${3:Integer};$0'#10'end;', 'declaration'),
    Snippet('prop', UiText(TSnippetsText.PropertyWithFieldAndSetter), UiText(TSnippetsText.DeclarationInTheClassPropset),
      'property ${1:Value}: ${2:Integer} read F${1} write Set${1};$0', 'class'),
    // Gleiche Form wie /prop, /changed und die Vorlage „changed“ des Servers (TSetterGenerator).
    Snippet('propset', UiText(TSnippetsText.SetterWithChangeCheck), UiText(TSnippetsText.SetsTheFieldOnlyWhen),
      'procedure ${1:TMyControl}.Set${2:Value}(const Value: ${3:Integer});'#10'begin'#10 +
      '  if F${2} <> Value then'#10'  begin'#10'    F${2} := Value;'#10'    Invalidate;$0'#10'  end;'#10'end;',
      'implementation'),
    Snippet('comp', UiText(TSnippetsText.ComponentSkeleton), UiText(TSnippetsText.ComponentWithPublishedSectionReg),
      '${1:TMyControl} = class(${2:TCustomControl})'#10'protected'#10'  procedure Paint; override;'#10 +
      'public'#10'  constructor Create(AOwner: TComponent); override;'#10'published'#10'  $0'#10'end;',
      'declaration'),
    Snippet('reg', UiText(TSnippetsText.RegisterProcedure), UiText(TSnippetsText.RegisterTheComponentInThe),
      'procedure Register;'#10'begin'#10'  RegisterComponents(''${1:Atlas}'', [${2:TMyControl}]);$0'#10'end;',
      'implementation')];
end;

class function TAtlasSnippets.ContextWords: TArray<string>;
begin
  Result := ['any', 'statement', 'declaration', 'routine', 'class', 'record', 'interfaceType', 'interface',
    'implementation', 'program'];
end;

class function TAtlasSnippets.FileKinds: TArray<string>;
begin
  Result := ['unit', 'form', 'test'];
end;

class function TAtlasSnippets.FileTemplates(const AList: TAtlasSnippetList): TAtlasSnippetList;
var
  mItem: TAtlasSnippet;
begin
  Result := nil;
  for mItem in AList do
  begin
    if mItem.FileKind <> '' then
    begin
      Result := Result + [mItem];
    end;
  end;
end;

class function TAtlasSnippets.WithoutFileTemplates(const AList: TAtlasSnippetList): TAtlasSnippetList;
var
  mItem: TAtlasSnippet;
begin
  Result := nil;
  for mItem in AList do
  begin
    if mItem.FileKind = '' then
    begin
      Result := Result + [mItem];
    end;
  end;
end;

class function TAtlasSnippets.FitsContext(const AContext: string; const APlaces: TArray<string>): Boolean;
var
  mWord: string;
  mInRoutine: Boolean;
begin
  if Trim(AContext) = '' then
  begin
    Exit(True);
  end;
  mInRoutine := IndexText('routine', APlaces) >= 0;
  for mWord in AContext.Split([',']) do
  begin
    if WordFits(Trim(mWord), APlaces, mInRoutine) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasSnippets.Merge(const ABuiltIn, AUser: TAtlasSnippetList): TAtlasSnippetList;
var
  mItem: TAtlasSnippet;
begin
  Result := nil;
  for mItem in ABuiltIn do
  begin
    if not ListHasPrefix(AUser, mItem.Prefix) then
    begin
      Result := Result + [mItem];
    end;
  end;
  // Doppelte Kürzel unter den neuen: die erste Datei gilt.
  for mItem in AUser do
  begin
    if not HasSameOrigin(Result, mItem) then
    begin
      Result := Result + [mItem];
    end;
  end;
end;

class function TAtlasSnippets.Postfixes(const AList: TAtlasSnippetList): TAtlasSnippetList;
var
  mItem: TAtlasSnippet;
begin
  Result := nil;
  for mItem in AList do
  begin
    if mItem.Postfix then
    begin
      Result := Result + [mItem];
    end;
  end;
end;

class function TAtlasSnippets.WithoutPostfix(const AList: TAtlasSnippetList): TAtlasSnippetList;
var
  mItem: TAtlasSnippet;
begin
  Result := nil;
  for mItem in AList do
  begin
    if not mItem.Postfix then
    begin
      Result := Result + [mItem];
    end;
  end;
end;

class function TAtlasSnippets.PostfixParams(const AList: TAtlasSnippetList): TJSONObject;
var
  mTemplates: TJSONArray;
  mItem: TAtlasSnippet;
  mEntry: TJSONObject;
  mDescription: string;
begin
  Result := TJSONObject.Create;
  mTemplates := TJSONArray.Create;
  Result.AddPair('templates', mTemplates);
  for mItem in Postfixes(AList) do
  begin
    mDescription := mItem.Description;
    if mDescription = '' then
    begin
      mDescription := mItem.Name;
    end;
    mEntry := TJSONObject.Create;
    mEntry.AddPair('key', mItem.Prefix);
    mEntry.AddPair('description', mDescription);
    mEntry.AddPair('body', mItem.Body);
    if mItem.TypeCondition <> '' then
    begin
      mEntry.AddPair('type', mItem.TypeCondition);
    end;
    mTemplates.AddElement(mEntry);
  end;
end;

class function TAtlasSnippets.Expand(const ABody, AIndent, ALineBreak: string): TAtlasSnippetExpansion;
var
  mParts: TArray<TSegment>;
  mDefaults: TArray<string>;
  mKnown: TArray<Boolean>;
  mIndex, mNumber, mHighest: Integer;
  mText: string;
  mStop: TAtlasSnippetStop;

  function Indented(const AValue: string): string;
  begin
    Result := StringReplace(NormalizeBreaks(AValue), #10, ALineBreak + AIndent, [rfReplaceAll]);
  end;

begin
  Result := Default(TAtlasSnippetExpansion);
  mParts := Segments(NormalizeBreaks(ABody));
  // Vorgabetext je Nummer: der erste vorhandene.
  mHighest := 0;
  for mIndex := 0 to High(mParts) do
  begin
    if mParts[mIndex].IsStop and (mParts[mIndex].Number > mHighest) then
    begin
      mHighest := mParts[mIndex].Number;
    end;
  end;
  SetLength(mDefaults, mHighest + 1);
  SetLength(mKnown, mHighest + 1);
  for mIndex := 0 to High(mParts) do
  begin
    if mParts[mIndex].IsStop and mParts[mIndex].HasDefault and not mKnown[mParts[mIndex].Number] then
    begin
      mDefaults[mParts[mIndex].Number] := mParts[mIndex].Text;
      mKnown[mParts[mIndex].Number] := True;
    end;
  end;
  mText := '';
  for mIndex := 0 to High(mParts) do
  begin
    if mParts[mIndex].IsStop then
    begin
      mNumber := mParts[mIndex].Number;
      mStop.Number := mNumber;
      mStop.Start := Length(mText);
      mText := mText + Indented(mDefaults[mNumber]);
      mStop.Length := Length(mText) - mStop.Start;
      Result.Stops := Result.Stops + [mStop];
    end
    else
    begin
      mText := mText + Indented(mParts[mIndex].Text);
    end;
  end;
  Result.Text := mText;
end;

function ConvertLsp(const AText: string; var AIndex: Integer; ATop: Boolean): string; forward;

/// <summary>"\" an AIndex: maskiertes Zeichen (auf oberster Ebene "\$" als "$$"), sonst "\" selbst.</summary>
function EscapeAt(const AText: string; var AIndex: Integer; ATop: Boolean): string;
begin
  if (AIndex < Length(AText)) and CharInSet(AText[AIndex + 1], ['\', '$', '}', ',', '|']) then
  begin
    Result := AText[AIndex + 1];
    if ATop and (Result = '$') then
    begin
      Result := '$$';
    end;
    Inc(AIndex, 2);
  end
  else
  begin
    Result := '\';
    Inc(AIndex);
  end;
end;

procedure SkipPast(const AText: string; var AIndex: Integer; AChar: Char);
begin
  while (AIndex <= Length(AText)) and (AText[AIndex] <> AChar) do
  begin
    Inc(AIndex);
  end;
  Inc(AIndex);
end;

/// <summary>Auswahl ${n|a,b|} ab hinter "|": die erste Möglichkeit als Vorgabe; AIndex danach hinter "}".</summary>
function ChoiceDefault(const AText: string; var AIndex: Integer): string;
var
  mStart: Integer;
begin
  mStart := AIndex;
  while (AIndex <= Length(AText)) and not CharInSet(AText[AIndex], [',', '|']) do
  begin
    Inc(AIndex);
  end;
  Result := Copy(AText, mStart, AIndex - mStart);
  SkipPast(AText, AIndex, '}');
end;

/// <summary>Vorgabe eines Platzhalters in Klammern ab hinter dem Namen; AIndex danach hinter "}".</summary>
function BracedDefault(const AText: string; var AIndex: Integer): string;
begin
  Result := '';
  if (AIndex <= Length(AText)) and (AText[AIndex] = ':') then
  begin
    Inc(AIndex);
    Result := ConvertLsp(AText, AIndex, False);
  end
  else if (AIndex <= Length(AText)) and (AText[AIndex] = '|') then
  begin
    Inc(AIndex);
    Result := ChoiceDefault(AText, AIndex);
  end
  else
  begin
    SkipPast(AText, AIndex, '}');
  end;
end;

/// <summary>Tabstopp nur auf oberster Ebene und mit Nummer; Variablen werden zu ihrer Vorgabe.</summary>
function StopText(const ANumber, ADefault: string; ATop: Boolean): string;
begin
  if not (ATop and (ANumber <> '') and IsDigit(ANumber[1])) then
  begin
    Result := ADefault;
  end
  else if (ADefault = '') and (ANumber = '0') then
  begin
    Result := '$0';
  end
  else if ADefault = '' then
  begin
    Result := '${' + ANumber + '}';
  end
  else
  begin
    Result := '${' + ANumber + ':' + ADefault + '}';
  end;
end;

/// <summary>$1, ${1}, ${1:Vorgabe}, ${1|a,b|}, ${NAME:Vorgabe} ab dem "$" an AIndex.</summary>
function PlaceholderAt(const AText: string; var AIndex: Integer; ATop: Boolean): string;
var
  mStart: Integer;
  mBraced: Boolean;
  mNumber, mDefault: string;
begin
  Inc(AIndex);
  mBraced := AText[AIndex] = '{';
  if mBraced then
  begin
    Inc(AIndex);
  end;
  mStart := AIndex;
  while (AIndex <= Length(AText)) and TTextChars.IsAsciiIdentChar(AText[AIndex]) do
  begin
    Inc(AIndex);
  end;
  mNumber := Copy(AText, mStart, AIndex - mStart);
  mDefault := '';
  if mBraced then
  begin
    mDefault := BracedDefault(AText, AIndex);
  end;
  Result := StopText(mNumber, mDefault, ATop);
end;

/// <summary>"$" an AIndex beginnt einen Platzhalter; "$" vor einem Buchstaben bleibt Text ($FF).</summary>
function IsPlaceholderStart(const AText: string; AIndex: Integer): Boolean;
begin
  Result := (AText[AIndex] = '$') and (AIndex < Length(AText)) and
    (IsDigit(AText[AIndex + 1]) or (AText[AIndex + 1] = '{'));
end;

/// <summary>Liest ab AIndex Klartext bis zum passenden "}" bzw. Textende (verschachtelte Platzhalter und Variablen
/// werden zu ihrer Vorgabe). Mit ATop entsteht das eigene Format ($$, ${n}, ${n:Vorgabe}).</summary>
function ConvertLsp(const AText: string; var AIndex: Integer; ATop: Boolean): string;
begin
  Result := '';
  while AIndex <= Length(AText) do
  begin
    if AText[AIndex] = '\' then
    begin
      Result := Result + EscapeAt(AText, AIndex, ATop);
    end
    else if (AText[AIndex] = '}') and not ATop then
    begin
      Inc(AIndex);
      Exit;
    end
    else if IsPlaceholderStart(AText, AIndex) then
    begin
      Result := Result + PlaceholderAt(AText, AIndex, ATop);
    end
    // Ein "$" ohne Platzhalter bleibt Text.
    else if ATop and (AText[AIndex] = '$') then
    begin
      Result := Result + '$$';
      Inc(AIndex);
    end
    else
    begin
      Result := Result + AText[AIndex];
      Inc(AIndex);
    end;
  end;
end;

class function TAtlasSnippets.FromLsp(const AText: string): string;
var
  mIndex: Integer;
begin
  mIndex := 1;
  Result := ConvertLsp(NormalizeBreaks(AText), mIndex, True);
end;

class function TAtlasSnippets.PlainText(const ABody: string): string;
begin
  Result := Expand(ABody, '', #10).Text;
end;

class function TAtlasSnippets.IndentOf(const ALine: string): string;
begin
  Result := TTextLines.IndentOf(ALine);
end;

class function TAtlasSnippets.FolderStamp(const APath: string): string;
var
  mSearch: TSearchRec;
begin
  Result := '';
  if (APath = '') or not DirectoryExists(APath) then
  begin
    Exit;
  end;
  Result := '+';
  if FindFirst(IncludeTrailingPathDelimiter(APath) + '*' + FileExtension, faAnyFile, mSearch) = 0 then
    try
      repeat
        Result := Result + mSearch.Name + '|' + IntToStr(mSearch.Size) + '|' + FormatDateTime('yyyymmddhhnnss', mSearch.TimeStamp) + ';';
      until FindNext(mSearch) <> 0;
    finally
      FindClose(mSearch);
    end;
end;

class function TAtlasSnippets.LoadFolder(const APath: string; out AErrors: TArray<string>): TAtlasSnippetList;
var
  mName: string;
begin
  Result := nil;
  AErrors := nil;
  if (APath = '') or not DirectoryExists(APath) then
  begin
    Exit;
  end;
  for mName in SnippetFileNames(APath) do
  begin
    LoadSnippetFile(APath, mName, Result, AErrors);
  end;
end;

initialization
  TAtlasTextLanguage.AddTable('Atlas.Core.Completion.Snippets', cTexts[TAtlasLanguage.German], cTexts[TAtlasLanguage.English]);

end.
