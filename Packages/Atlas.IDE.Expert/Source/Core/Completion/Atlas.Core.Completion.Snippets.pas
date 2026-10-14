unit Atlas.Core.Completion.Snippets;

// Code-Vorlagen (#51): Format der Dateien *.atlas-snippet, mitgelieferte
// Vorlagen und das Einsetzen mit Platzhaltern, ohne Editor.
//
// Dateiformat: Kopfzeilen "Schlüssel: Wert" (name, prefix, description), dann
// eine Zeile "---" und der Text der Vorlage. Zeilen mit "#" im Kopf sind
// Kommentare. Platzhalter im Text:
//   ${1:List}  Platzhalter 1 mit Vorgabetext
//   ${2}       Platzhalter 2 ohne Vorgabe
//   $0, ${0}   Cursor nach dem letzten Platzhalter
// Wiederholte Nummern sind verknüpft und zeigen denselben Text. Ein "$" vor
// etwas anderem bleibt stehen, auch "$0F" oder "$FF": Hexzahlen im Delphi-Code
// sind keine Platzhalter. "$$" steht für ein einzelnes "$" (für Text wie
// "$1;", der sonst wie ein Platzhalter aussähe; so übernimmt Atlas die Live
// Templates der IDE).

interface

uses
  System.SysUtils;

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
    /// <summary>tryf, trye, forin, fori, while, repeat, class, record, prop, propset, comp, reg.</summary>
    class function BuiltIn: TAtlasSnippetList; static;
    /// <summary>Vorlagen aus AUser ersetzen die aus ABuiltIn mit gleichem Kürzel (ohne Groß/Klein). Für
    /// mitgelieferte, IDE- und eigene Vorlagen zweimal: Merge(Merge(BuiltIn, Ide), User).</summary>
    class function Merge(const ABuiltIn, AUser: TAtlasSnippetList): TAtlasSnippetList; static;
    /// <summary>Setzt ABody ein: jede Zeile nach der ersten bekommt AIndent vorangestellt, Zeilenumbrüche werden
    /// zu ALineBreak, Platzhalter zu ihrem Vorgabetext (verknüpfte zum ersten vorhandenen).</summary>
    class function Expand(const ABody, AIndent, ALineBreak: string): TAtlasSnippetExpansion; static;
    /// <summary>Klartext ohne Platzhalter, Zeilen mit #10; für Vorschau und Detailpanel.</summary>
    class function PlainText(const ABody: string): string; static;
    /// <summary>Einrückung am Anfang von ALine (Leerzeichen und Tabs).</summary>
    class function IndentOf(const ALine: string): string; static;
    /// <summary>Stand des Ordners (Namen, Größen, Zeitstempel der Vorlagendateien); ändert sich, sobald eine
    /// Datei dazukommt, wegfällt oder gespeichert wird. '' ohne Ordner.</summary>
    class function FolderStamp(const APath: string): string; static;
    /// <summary>Alle *.atlas-snippet in APath; Fehler je Datei in AErrors ("Datei: Meldung").</summary>
    class function LoadFolder(const APath: string; out AErrors: TArray<string>): TAtlasSnippetList; static;
  end;

implementation

uses
  System.Classes;

type
  TSegment = record
    IsStop: Boolean;
    Number: Integer;
    HasDefault: Boolean;
    Text: string;
  end;

function IsDigit(C: Char): Boolean;
begin
  Result := (C >= '0') and (C <= '9');
end;

function IsWordChar(C: Char): Boolean;
begin
  Result := IsDigit(C) or ((C >= 'A') and (C <= 'Z')) or ((C >= 'a') and (C <= 'z')) or (C = '_');
end;

function NormalizeBreaks(const AText: string): string;
begin
  Result := StringReplace(StringReplace(AText, #13#10, #10, [rfReplaceAll]), #13, #10, [rfReplaceAll]);
end;

/// <summary>Zerlegt den Text in Klartext und Platzhalter.</summary>
function Segments(const ABody: string): TArray<TSegment>;
var
  Index, Close, Colon, Number: Integer;
  Literal: string;
  Segment: TSegment;
  Inner: string;

  procedure FlushLiteral;
  begin
    if Literal = '' then
      Exit;
    Segment := Default(TSegment);
    Segment.Text := Literal;
    Result := Result + [Segment];
    Literal := '';
  end;

begin
  Result := nil;
  Literal := '';
  Index := 1;
  while Index <= Length(ABody) do
  begin
    if ABody[Index] = '$' then
    begin
      // "$$" = "$"
      if (Index < Length(ABody)) and (ABody[Index + 1] = '$') then
      begin
        Literal := Literal + '$';
        Inc(Index, 2);
        Continue;
      end;
      // ${n} bzw. ${n:Vorgabe}
      if (Index < Length(ABody)) and (ABody[Index + 1] = '{') and (Index + 2 <= Length(ABody)) and
        IsDigit(ABody[Index + 2]) then
      begin
        Close := Index + 2;
        while (Close <= Length(ABody)) and (ABody[Close] <> '}') and (ABody[Close] <> #10) do
          Inc(Close);
        if (Close <= Length(ABody)) and (ABody[Close] = '}') then
        begin
          Inner := Copy(ABody, Index + 2, Close - Index - 2);
          Colon := Pos(':', Inner);
          if Colon = 0 then
            Colon := Length(Inner) + 1;
          if TryStrToInt(Copy(Inner, 1, Colon - 1), Number) and (Number >= 0) then
          begin
            FlushLiteral;
            Segment := Default(TSegment);
            Segment.IsStop := True;
            Segment.Number := Number;
            Segment.HasDefault := Colon <= Length(Inner);
            Segment.Text := Copy(Inner, Colon + 1, MaxInt);
            Result := Result + [Segment];
            Index := Close + 1;
            Continue;
          end;
        end;
      end;
      // $0 allein, nicht $0F
      if (Index < Length(ABody)) and (ABody[Index + 1] = '0') and
        ((Index + 2 > Length(ABody)) or not IsWordChar(ABody[Index + 2])) then
      begin
        FlushLiteral;
        Segment := Default(TSegment);
        Segment.IsStop := True;
        Result := Result + [Segment];
        Inc(Index, 2);
        Continue;
      end;
    end;
    Literal := Literal + ABody[Index];
    Inc(Index);
  end;
  FlushLiteral;
end;

{ TAtlasSnippetExpansion }

function TAtlasSnippetExpansion.HasPlaceholders: Boolean;
var
  Stop: TAtlasSnippetStop;
begin
  Result := False;
  for Stop in Stops do
    if Stop.Number > 0 then
      Exit(True);
end;

{ TAtlasSnippets }

class function TAtlasSnippets.Parse(const AText, AFileName: string; out ASnippet: TAtlasSnippet;
  out AError: string): Boolean;
var
  Lines: TArray<string>;
  Index, Separator, Colon: Integer;
  Line, Key, Value, Body: string;
begin
  Result := False;
  ASnippet := Default(TAtlasSnippet);
  ASnippet.Origin := TAtlasSnippetOrigin.User;
  ASnippet.FileName := AFileName;
  AError := '';
  Lines := NormalizeBreaks(AText).Split([#10]);
  Separator := -1;
  for Index := 0 to High(Lines) do
  begin
    Line := Trim(Lines[Index]);
    if Line = '---' then
    begin
      Separator := Index;
      Break;
    end;
    if (Line = '') or (Line[1] = '#') then
      Continue;
    Colon := Pos(':', Line);
    if Colon = 0 then
    begin
      AError := Format('Zeile %d: "Schlüssel: Wert" oder "---" erwartet', [Index + 1]);
      Exit;
    end;
    Key := LowerCase(Trim(Copy(Line, 1, Colon - 1)));
    Value := Trim(Copy(Line, Colon + 1, MaxInt));
    if Key = 'name' then
      ASnippet.Name := Value
    else if Key = 'prefix' then
      ASnippet.Prefix := Value
    else if Key = 'description' then
      ASnippet.Description := Value
    else
    begin
      AError := Format('Zeile %d: unbekannter Schlüssel "%s" (erlaubt: name, prefix, description)',
        [Index + 1, Key]);
      Exit;
    end;
  end;
  if Separator < 0 then
  begin
    AError := 'Zeile "---" zwischen Kopf und Text fehlt';
    Exit;
  end;
  if ASnippet.Prefix = '' then
  begin
    AError := 'Schlüssel "prefix" fehlt';
    Exit;
  end;
  for Index := 1 to Length(ASnippet.Prefix) do
    if not IsWordChar(ASnippet.Prefix[Index]) then
    begin
      AError := Format('Kürzel "%s": nur Buchstaben, Ziffern und _', [ASnippet.Prefix]);
      Exit;
    end;
  Body := '';
  for Index := Separator + 1 to High(Lines) do
  begin
    if Index > Separator + 1 then
      Body := Body + #10;
    Body := Body + Lines[Index];
  end;
  // Leerzeilen am Ende gehören nicht zur Vorlage.
  while (Body <> '') and ((Body[Length(Body)] = #10) or (Body[Length(Body)] = ' ')) do
    Delete(Body, Length(Body), 1);
  if Trim(Body) = '' then
  begin
    AError := 'Text der Vorlage fehlt';
    Exit;
  end;
  ASnippet.Body := Body;
  if ASnippet.Name = '' then
    ASnippet.Name := ASnippet.Prefix;
  Result := True;
end;

class function TAtlasSnippets.ToFileText(const ASnippet: TAtlasSnippet): string;

  function OneLine(const AText: string): string;
  begin
    Result := Trim(StringReplace(NormalizeBreaks(AText), #10, ' ', [rfReplaceAll]));
  end;

begin
  Result := 'name: ' + OneLine(ASnippet.Name) + #10 + 'prefix: ' + OneLine(ASnippet.Prefix) + #10 +
    'description: ' + OneLine(ASnippet.Description) + #10 + '---' + #10 + NormalizeBreaks(ASnippet.Body) + #10;
end;

class function TAtlasSnippets.FileNameFor(const APrefix: string): string;
var
  Index: Integer;
begin
  Result := APrefix;
  for Index := 1 to Length(Result) do
    if not IsWordChar(Result[Index]) then
      Result[Index] := '_';
  Result := Result + FileExtension;
end;

function Snippet(const APrefix, AName, ADescription, ABody: string): TAtlasSnippet;
begin
  Result := Default(TAtlasSnippet);
  Result.Prefix := APrefix;
  Result.Name := AName;
  Result.Description := ADescription;
  Result.Body := ABody;
  Result.Origin := TAtlasSnippetOrigin.BuiltIn;
end;

class function TAtlasSnippets.BuiltIn: TAtlasSnippetList;
begin
  Result := [
    Snippet('tryf', 'try…finally mit Create/Free', 'Objekt anlegen und sicher wieder freigeben.',
      '${1:List} := ${2:TStringList}.Create;'#10'try'#10'  $0'#10'finally'#10'  ${1}.Free;'#10'end;'),
    Snippet('trye', 'try…except', 'Ausnahme einer Klasse behandeln.',
      'try'#10'  $0'#10'except'#10'  on E: ${1:Exception} do'#10'    ${2:raise};'#10'end;'),
    Snippet('forin', 'for…in-Schleife', 'Über die Elemente einer Liste laufen (Inline-Variable).',
      'for var ${1:Item} in ${2:List} do'#10'begin'#10'  $0'#10'end;'),
    Snippet('fori', 'for-Schleife mit Zähler', 'Von 0 bis Count - 1 zählen (Inline-Variable).',
      'for var ${1:I} := ${2:0} to ${3:List.Count - 1} do'#10'begin'#10'  $0'#10'end;'),
    Snippet('while', 'while-Schleife', 'Solange die Bedingung gilt.',
      'while ${1:Condition} do'#10'begin'#10'  $0'#10'end;'),
    Snippet('repeat', 'repeat…until-Schleife', 'Mindestens einmal, bis die Bedingung gilt.',
      'repeat'#10'  $0'#10'until ${1:Condition};'),
    Snippet('class', 'Klasse mit Konstruktor und Destruktor', 'Klassendeklaration im type-Abschnitt.',
      '${1:TMyClass} = class(${2:TObject})'#10'private'#10'  $0'#10'public'#10'  constructor Create;'#10 +
      '  destructor Destroy; override;'#10'end;'),
    Snippet('record', 'Record', 'Record-Deklaration im type-Abschnitt.',
      '${1:TMyRecord} = record'#10'  ${2:Value}: ${3:Integer};$0'#10'end;'),
    Snippet('prop', 'Property mit Feld und Setter', 'Deklaration in der Klasse; den Setter legt propset an.',
      'property ${1:Value}: ${2:Integer} read F${1} write Set${1};$0'),
    Snippet('propset', 'Setter mit Prüfung auf Änderung', 'Setzt das Feld nur bei Änderung und zeichnet neu.',
      'procedure ${1:TMyControl}.Set${2:Value}(const AValue: ${3:Integer});'#10'begin'#10 +
      '  if F${2} = AValue then'#10'    Exit;'#10'  F${2} := AValue;'#10'  Invalidate;$0'#10'end;'),
    Snippet('comp', 'Komponentengerüst', 'Komponente mit published-Abschnitt; die Registrierung legt reg an.',
      '${1:TMyControl} = class(${2:TCustomControl})'#10'protected'#10'  procedure Paint; override;'#10 +
      'public'#10'  constructor Create(AOwner: TComponent); override;'#10'published'#10'  $0'#10'end;'),
    Snippet('reg', 'Register-Prozedur', 'Komponente in der Palette registrieren.',
      'procedure Register;'#10'begin'#10'  RegisterComponents(''${1:Atlas}'', [${2:TMyControl}]);$0'#10'end;')];
end;

class function TAtlasSnippets.Merge(const ABuiltIn, AUser: TAtlasSnippetList): TAtlasSnippetList;
var
  Item, Own: TAtlasSnippet;
  Replaced: Boolean;
begin
  Result := nil;
  for Item in ABuiltIn do
  begin
    Replaced := False;
    for Own in AUser do
      if SameText(Own.Prefix, Item.Prefix) then
        Replaced := True;
    if not Replaced then
      Result := Result + [Item];
  end;
  for Own in AUser do
  begin
    Replaced := False;
    // Doppelte Kürzel unter den neuen: die erste Datei gilt.
    for Item in Result do
      if (Item.Origin = Own.Origin) and SameText(Own.Prefix, Item.Prefix) then
        Replaced := True;
    if not Replaced then
      Result := Result + [Own];
  end;
end;

class function TAtlasSnippets.Expand(const ABody, AIndent, ALineBreak: string): TAtlasSnippetExpansion;
var
  Parts: TArray<TSegment>;
  Defaults: TArray<string>;
  Known: TArray<Boolean>;
  Index, Number, Highest: Integer;
  Text: string;
  Stop: TAtlasSnippetStop;

  function Indented(const AValue: string): string;
  begin
    Result := StringReplace(NormalizeBreaks(AValue), #10, ALineBreak + AIndent, [rfReplaceAll]);
  end;

begin
  Result := Default(TAtlasSnippetExpansion);
  Parts := Segments(NormalizeBreaks(ABody));
  // Vorgabetext je Nummer: der erste vorhandene.
  Highest := 0;
  for Index := 0 to High(Parts) do
    if Parts[Index].IsStop and (Parts[Index].Number > Highest) then
      Highest := Parts[Index].Number;
  SetLength(Defaults, Highest + 1);
  SetLength(Known, Highest + 1);
  for Index := 0 to High(Parts) do
    if Parts[Index].IsStop and Parts[Index].HasDefault and not Known[Parts[Index].Number] then
    begin
      Defaults[Parts[Index].Number] := Parts[Index].Text;
      Known[Parts[Index].Number] := True;
    end;
  Text := '';
  for Index := 0 to High(Parts) do
    if Parts[Index].IsStop then
    begin
      Number := Parts[Index].Number;
      Stop.Number := Number;
      Stop.Start := Length(Text);
      Text := Text + Indented(Defaults[Number]);
      Stop.Length := Length(Text) - Stop.Start;
      Result.Stops := Result.Stops + [Stop];
    end
    else
      Text := Text + Indented(Parts[Index].Text);
  Result.Text := Text;
end;

class function TAtlasSnippets.PlainText(const ABody: string): string;
begin
  Result := Expand(ABody, '', #10).Text;
end;

class function TAtlasSnippets.IndentOf(const ALine: string): string;
var
  Index: Integer;
begin
  Index := 1;
  while (Index <= Length(ALine)) and ((ALine[Index] = ' ') or (ALine[Index] = #9)) do
    Inc(Index);
  Result := Copy(ALine, 1, Index - 1);
end;

class function TAtlasSnippets.FolderStamp(const APath: string): string;
var
  Search: TSearchRec;
begin
  Result := '';
  if (APath = '') or not DirectoryExists(APath) then
    Exit;
  Result := '+';
  if FindFirst(IncludeTrailingPathDelimiter(APath) + '*' + FileExtension, faAnyFile, Search) = 0 then
    try
      repeat
        Result := Result + Search.Name + '|' + IntToStr(Search.Size) + '|' + IntToStr(Search.Time) + ';';
      until FindNext(Search) <> 0;
    finally
      FindClose(Search);
    end;
end;

class function TAtlasSnippets.LoadFolder(const APath: string; out AErrors: TArray<string>): TAtlasSnippetList;
var
  Search: TSearchRec;
  Names: TStringList;
  Lines: TStringList;
  Index: Integer;
  Item: TAtlasSnippet;
  Error, FileName: string;
begin
  Result := nil;
  AErrors := nil;
  if (APath = '') or not DirectoryExists(APath) then
    Exit;
  Names := TStringList.Create;
  try
    if FindFirst(IncludeTrailingPathDelimiter(APath) + '*' + FileExtension, faAnyFile, Search) = 0 then
      try
        repeat
          if (Search.Attr and faDirectory) = 0 then
            Names.Add(Search.Name);
        until FindNext(Search) <> 0;
      finally
        FindClose(Search);
      end;
    // Feste Reihenfolge, damit bei doppelten Kürzeln immer dieselbe Datei gilt.
    Names.Sort;
    for Index := 0 to Names.Count - 1 do
    begin
      FileName := IncludeTrailingPathDelimiter(APath) + Names[Index];
      Lines := TStringList.Create;
      try
        try
          Lines.LoadFromFile(FileName, TEncoding.UTF8);
          if Parse(Lines.Text, FileName, Item, Error) then
            Result := Result + [Item]
          else
            AErrors := AErrors + [Names[Index] + ': ' + Error];
        except
          on E: Exception do
            AErrors := AErrors + [Names[Index] + ': ' + E.Message];
        end;
      finally
        Lines.Free;
      end;
    end;
  finally
    Names.Free;
  end;
end;

end.
