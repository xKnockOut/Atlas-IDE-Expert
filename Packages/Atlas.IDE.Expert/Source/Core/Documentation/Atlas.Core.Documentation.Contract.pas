unit Atlas.Core.Documentation.Contract;

// Strukturierte XMLDoc (#654) aus "atlas.documentation" der Hover-Antwort bzw.
// "data.atlas.documentation" der Resolve-Antwort: Abschnitte (summary, param,
// typeparam, returns, value, exception, remarks, example, seealso) mit Läufen
// (Text, Code, Verweis mit Fundort, Link, Absatz, Codeblock, Listenpunkt,
// Tabellenzelle). Dazu Begründungen (#1123) als Abschnitte rationale, je
// Eintrag einer mit der Marke als Name; ein Link "issue:312" darin zeigt auf ein
// Issue im Tracker (TAtlasDocIssueUrl). Dazu die Anzeige-Einstellungen "xmlDoc" (zu- oder aufgeklappt
// beim Öffnen, Zeilengrenze), die der Server je Projekt meldet, und die
// Parameter der Signatur (#770) aus der Deklaration (Name, Art, Typ;
// Ergebnistyp), damit die Doku jeden Parameter in der Reihenfolge der Signatur
// zeigen kann. Den Zustand „wie zuletzt“ hält TAtlasDocExpandState in
// Atlas.Core.Documentation.Layout.

interface

uses
  System.JSON;

{$SCOPEDENUMS ON}

type
  /// <summary>Art eines Laufs; Namen wie im Server (text, code, ref, link, paramref, keyword, br, para,
  /// codeblock, bullet, cell).</summary>
  TAtlasDocRunKind = (Text, Code, Ref, Link, ParamRef, Keyword, LineBreak, Paragraph, CodeBlock, Bullet, Cell);

  TAtlasDocSectionKind = (Summary, Param, TypeParam, Returns, Value, Exception, Remarks, Example, SeeAlso, Rationale);

  /// <summary>Adresse des Issues AKey ("312") im Tracker des aktuellen Projekts; '' ohne Tracker.</summary>
  TAtlasDocIssueUrl = reference to function(const AKey: string): string;

  /// <summary>XMLDoc beim Öffnen (#770, hints.xmlDocExpand): immer zugeklappt, wie zuletzt, immer aufgeklappt.
  /// </summary>
  TAtlasDocExpand = (Collapsed, Last, Expanded);

  /// <summary>Wo die Doku steht; „wie zuletzt“ gilt je Fläche.</summary>
  TAtlasDocSurface = (Tooltip, Details);

  /// <summary>Ziel eines Verweises; FileName '' ohne Fundort (Name, Unit bleiben).</summary>
  TAtlasDocTarget = record
    Name: string;
    UnitName: string;
    FileName: string;
    /// <summary>0-basiert.</summary>
    Line: Integer;
    Character: Integer;
    function HasLocation: Boolean;
    class function FromJson(const AObject: TJSONObject): TAtlasDocTarget; static;
  end;

  TAtlasDocRun = record
    Kind: TAtlasDocRunKind;
    Text: string;
    /// <summary>Ref: cref (ohne Präfix); Link: URL; CodeBlock: Sprache ('' = Delphi; Markdown der Issue-Vorschau,
    /// #1264); Bullet: Ziel der anklickbaren Marke ('' = nur Marke; Kästchen einer Checkliste, #1273).</summary>
    Target: string;
    Bold: Boolean;
    Italic: Boolean;
    /// <summary>Bullet: Listenebene ab 1.</summary>
    Level: Integer;
    /// <summary>Ref: Fundort, wenn der Server ihn kennt.</summary>
    Location: TAtlasDocTarget;
    class function Create(AKind: TAtlasDocRunKind; const AText: string;
      const ATarget: string = ''): TAtlasDocRun; static;
    /// <summary>CodeBlock in Delphi (ohne Sprache, pascal, delphi, objectpascal, pas, dpr): eingefärbt.</summary>
    function IsDelphiCode: Boolean;
  end;

  TAtlasDocRuns = TArray<TAtlasDocRun>;

  TAtlasDocSection = record
    Kind: TAtlasDocSectionKind;
    /// <summary>Param, TypeParam: Name; Exception: Klasse; Rationale: Marke (WHY).</summary>
    Name: string;
    /// <summary>Exception: Fundort der Klasse, wenn bekannt.</summary>
    NameRef: TAtlasDocTarget;
    Runs: TAtlasDocRuns;
    /// <summary>Text der Läufe ohne Auszeichnung (für Sprachausgabe und Tests).</summary>
    function Text: string;
  end;

  TAtlasDoc = record
    Sections: TArray<TAtlasDocSection>;
    function IsEmpty: Boolean;
    function Has(AKind: TAtlasDocSectionKind): Boolean;
    /// <summary>Abschnitte der Art AKind in Reihenfolge.</summary>
    function SectionsOf(AKind: TAtlasDocSectionKind): TArray<TAtlasDocSection>;
    /// <summary>Objekt mit "sections"; nil bzw. anderes ergibt eine leere Doku.</summary>
    class function FromJson(const AValue: TJSONValue): TAtlasDoc; static;
    /// <summary>Klartext fremder Server als eine Beschreibung: Zeilenumbrüche bleiben, Leerzeilen trennen
    /// Absätze, eingerückte Zeilen behalten ihre Einrückung.</summary>
    class function FromText(const AText: string): TAtlasDoc; static;
    class function TryParseRunKind(const AName: string; out AKind: TAtlasDocRunKind): Boolean; static;
    class function TryParseSectionKind(const AName: string; out AKind: TAtlasDocSectionKind): Boolean; static;
  end;

  /// <summary>Anzeige der XMLDoc (#654, #770): zu- oder aufgeklappt beim Öffnen und höchstens MaxLines Zeilen
  /// ohne Scrollen (0 = bis zur Bildschirmhöhe).</summary>
  TAtlasDocDisplay = record
  public const
    MaxMaxLines = 50;
  public
    /// <summary>Vom Server gemeldet (atlas.json bzw. Einstellungen des Plugins).</summary>
    Known: Boolean;
    Expand: TAtlasDocExpand;
    MaxLines: Integer;
    class function Create(AExpand: TAtlasDocExpand; AMaxLines: Integer): TAtlasDocDisplay; static;
    /// <summary>"xmlDoc" der Antwort; ohne Angabe AFallback (Einstellungen des Plugins). Liest "expand" und
    /// das frühere "full" (true = aufgeklappt).</summary>
    class function FromJson(const AValue: TJSONValue; const AFallback: TAtlasDocDisplay): TAtlasDocDisplay; static;
    /// <summary>"collapsed", "last", "expanded"; Unbekanntes ergibt Last.</summary>
    class function ExpandOf(const AName: string): TAtlasDocExpand; static;
    class function ExpandName(AExpand: TAtlasDocExpand): string; static;
  end;

  /// <summary>Parameter der Signatur: Name, Art (const, var, out, constref; '' ohne) und Typ ('' ohne).</summary>
  TAtlasDocParam = record
    Name: string;
    Modifier: string;
    TypeName: string;
    /// <summary>"const string", "out TCompilerMessage", "var" (untypisiert); '' ohne Art und Typ.</summary>
    function TypeText: string;
  end;

  /// <summary>Signatur aus der Deklaration (#770); Known = Parameterliste erkannt (auch leer).</summary>
  TAtlasDocSignature = record
    Known: Boolean;
    /// <summary>Property: ResultType ist ihr Typ (Abschnitt WERT statt RÜCKGABE).</summary>
    IsProperty: Boolean;
    Params: TArray<TAtlasDocParam>;
    /// <summary>Ergebnistyp einer Funktion bzw. Typ einer Property; '' ohne.</summary>
    ResultType: string;
    function IndexOf(const AName: string): Integer;
    function HasTypes: Boolean;
    /// <summary>Liest "function TX.Name(const A, B: string; out C: TFoo = nil): Boolean; overload;",
    /// Properties mit [..]-Parametern und Generics; Unbekanntes ergibt Known = False.</summary>
    class function Parse(const ADeclaration: string): TAtlasDocSignature; static;
  end;

implementation

uses
  System.SysUtils,
  System.Math;

const
  RunKindNames: array[TAtlasDocRunKind] of string = ('text', 'code', 'ref', 'link', 'paramref', 'keyword', 'br',
    'para', 'codeblock', 'bullet', 'cell');
  SectionKindNames: array[TAtlasDocSectionKind] of string = ('summary', 'param', 'typeparam', 'returns', 'value',
    'exception', 'remarks', 'example', 'seealso', 'rationale');

{ TAtlasDocTarget }

function TAtlasDocTarget.HasLocation: Boolean;
begin
  Result := FileName <> '';
end;

class function TAtlasDocTarget.FromJson(const AObject: TJSONObject): TAtlasDocTarget;
begin
  Result := Default(TAtlasDocTarget);
  if AObject = nil then
    Exit;
  Result.Name := AObject.GetValue<string>('name', '');
  Result.UnitName := AObject.GetValue<string>('unit', '');
  Result.FileName := AObject.GetValue<string>('file', '');
  Result.Line := AObject.GetValue<Integer>('line', 0);
  Result.Character := AObject.GetValue<Integer>('character', 0);
end;

{ TAtlasDocRun }

class function TAtlasDocRun.Create(AKind: TAtlasDocRunKind; const AText, ATarget: string): TAtlasDocRun;
begin
  Result := Default(TAtlasDocRun);
  Result.Kind := AKind;
  Result.Text := AText;
  Result.Target := ATarget;
end;

function TAtlasDocRun.IsDelphiCode: Boolean;
var
  mLanguage: string;
begin
  mLanguage := LowerCase(Trim(Target));
  Result := (mLanguage = '') or (mLanguage = 'pascal') or (mLanguage = 'delphi') or (mLanguage = 'objectpascal') or
    (mLanguage = 'object-pascal') or (mLanguage = 'pas') or (mLanguage = 'dpr');
end;

{ TAtlasDocSection }

function TAtlasDocSection.Text: string;
var
  Run: TAtlasDocRun;
begin
  Result := '';
  for Run in Runs do
    case Run.Kind of
      TAtlasDocRunKind.LineBreak, TAtlasDocRunKind.Paragraph:
        Result := Result + #10;
      TAtlasDocRunKind.CodeBlock:
        Result := Result + #10 + Run.Text + #10;
      TAtlasDocRunKind.Bullet:
        if Run.Text = '' then
          Result := Result + #10
        else
          Result := Result + #10 + Run.Text + ' ';
      TAtlasDocRunKind.Cell:
        Result := Result + ' – ';
    else
      Result := Result + Run.Text;
    end;
  Result := Trim(Result);
end;

{ TAtlasDoc }

function TAtlasDoc.IsEmpty: Boolean;
begin
  Result := Length(Sections) = 0;
end;

function TAtlasDoc.Has(AKind: TAtlasDocSectionKind): Boolean;
var
  Section: TAtlasDocSection;
begin
  for Section in Sections do
    if Section.Kind = AKind then
      Exit(True);
  Result := False;
end;

function TAtlasDoc.SectionsOf(AKind: TAtlasDocSectionKind): TArray<TAtlasDocSection>;
var
  Section: TAtlasDocSection;
begin
  Result := nil;
  for Section in Sections do
    if Section.Kind = AKind then
      Result := Result + [Section];
end;

class function TAtlasDoc.TryParseRunKind(const AName: string; out AKind: TAtlasDocRunKind): Boolean;
var
  Kind: TAtlasDocRunKind;
begin
  for Kind := Low(TAtlasDocRunKind) to High(TAtlasDocRunKind) do
    if SameText(RunKindNames[Kind], AName) then
    begin
      AKind := Kind;
      Exit(True);
    end;
  Result := False;
end;

class function TAtlasDoc.TryParseSectionKind(const AName: string; out AKind: TAtlasDocSectionKind): Boolean;
var
  Kind: TAtlasDocSectionKind;
begin
  for Kind := Low(TAtlasDocSectionKind) to High(TAtlasDocSectionKind) do
    if SameText(SectionKindNames[Kind], AName) then
    begin
      AKind := Kind;
      Exit(True);
    end;
  Result := False;
end;

class function TAtlasDoc.FromJson(const AValue: TJSONValue): TAtlasDoc;
var
  List, Runs: TJSONArray;
  Item, RunItem: TJSONValue;
  Ref: TJSONValue;
  Section: TAtlasDocSection;
  Run: TAtlasDocRun;
  SectionKind: TAtlasDocSectionKind;
  RunKind: TAtlasDocRunKind;
begin
  Result := Default(TAtlasDoc);
  if not (AValue is TJSONObject) then
    Exit;
  List := nil;
  if not TJSONObject(AValue).TryGetValue<TJSONArray>('sections', List) then
    Exit;
  for Item in List do
  begin
    // Unbekannte Abschnitte und Läufe (neuerer Server) überspringen statt abbrechen.
    if not (Item is TJSONObject) or
      not TryParseSectionKind(TJSONObject(Item).GetValue<string>('kind', ''), SectionKind) then
      Continue;
    Section := Default(TAtlasDocSection);
    Section.Kind := SectionKind;
    Section.Name := TJSONObject(Item).GetValue<string>('name', '');
    Ref := TJSONObject(Item).GetValue('ref');
    if Ref is TJSONObject then
    begin
      Section.NameRef := TAtlasDocTarget.FromJson(TJSONObject(Ref));
      if Section.NameRef.Name = '' then
        Section.NameRef.Name := Section.Name;
    end;
    Runs := nil;
    if TJSONObject(Item).TryGetValue<TJSONArray>('runs', Runs) then
      for RunItem in Runs do
      begin
        if not (RunItem is TJSONObject) or
          not TryParseRunKind(TJSONObject(RunItem).GetValue<string>('kind', ''), RunKind) then
          Continue;
        Run := TAtlasDocRun.Create(RunKind, TJSONObject(RunItem).GetValue<string>('text', ''),
          TJSONObject(RunItem).GetValue<string>('target', ''));
        Run.Bold := TJSONObject(RunItem).GetValue<Boolean>('bold', False);
        Run.Italic := TJSONObject(RunItem).GetValue<Boolean>('italic', False);
        Run.Level := TJSONObject(RunItem).GetValue<Integer>('level', 0);
        if RunKind = TAtlasDocRunKind.Ref then
        begin
          Run.Location := TAtlasDocTarget.FromJson(TJSONObject(RunItem));
          if Run.Location.Name = '' then
            Run.Location.Name := Run.Target;
        end;
        Section.Runs := Section.Runs + [Run];
      end;
    Result.Sections := Result.Sections + [Section];
  end;
end;

class function TAtlasDoc.FromText(const AText: string): TAtlasDoc;
var
  Section: TAtlasDocSection;
  Line: string;
  Pending: TAtlasDocRunKind;
  HasPending: Boolean;
  Last: Integer;
begin
  Result := Default(TAtlasDoc);
  if Trim(AText) = '' then
    Exit;
  Section := Default(TAtlasDocSection);
  Section.Kind := TAtlasDocSectionKind.Summary;
  HasPending := False;
  Pending := TAtlasDocRunKind.LineBreak;
  for Line in Trim(StringReplace(AText, #13#10, #10, [rfReplaceAll])).Split([#10]) do
  begin
    if Trim(Line) = '' then
    begin
      Pending := TAtlasDocRunKind.Paragraph;
      HasPending := Length(Section.Runs) > 0;
      Continue;
    end;
    Last := High(Section.Runs);
    // Eingerückte Zeilen (Code, Beispiele) als Codeblock mit Einrückung; aufeinanderfolgende in einem.
    if Line.StartsWith(' ') and (Last >= 0) and (Section.Runs[Last].Kind = TAtlasDocRunKind.CodeBlock) and
      (Pending = TAtlasDocRunKind.LineBreak) then
    begin
      Section.Runs[Last].Text := Section.Runs[Last].Text + #10 + TrimRight(Line);
      Continue;
    end;
    if HasPending then
      Section.Runs := Section.Runs + [TAtlasDocRun.Create(Pending, '')];
    if Line.StartsWith(' ') then
      Section.Runs := Section.Runs + [TAtlasDocRun.Create(TAtlasDocRunKind.CodeBlock, TrimRight(Line))]
    else
      Section.Runs := Section.Runs + [TAtlasDocRun.Create(TAtlasDocRunKind.Text, TrimRight(Line))];
    HasPending := True;
    Pending := TAtlasDocRunKind.LineBreak;
  end;
  Result.Sections := [Section];
end;

{ TAtlasDocDisplay }

const
  ExpandNames: array[TAtlasDocExpand] of string = ('collapsed', 'last', 'expanded');

class function TAtlasDocDisplay.Create(AExpand: TAtlasDocExpand; AMaxLines: Integer): TAtlasDocDisplay;
begin
  Result.Known := False;
  Result.Expand := AExpand;
  Result.MaxLines := EnsureRange(AMaxLines, 0, MaxMaxLines);
end;

class function TAtlasDocDisplay.ExpandOf(const AName: string): TAtlasDocExpand;
var
  Expand: TAtlasDocExpand;
begin
  for Expand := Low(TAtlasDocExpand) to High(TAtlasDocExpand) do
    if SameText(ExpandNames[Expand], Trim(AName)) then
      Exit(Expand);
  Result := TAtlasDocExpand.Last;
end;

class function TAtlasDocDisplay.ExpandName(AExpand: TAtlasDocExpand): string;
begin
  Result := ExpandNames[AExpand];
end;

class function TAtlasDocDisplay.FromJson(const AValue: TJSONValue;
  const AFallback: TAtlasDocDisplay): TAtlasDocDisplay;
var
  Full: TJSONValue;
begin
  Result := AFallback;
  if not (AValue is TJSONObject) then
    Exit;
  Result.Known := True;
  if TJSONObject(AValue).GetValue('expand') is TJSONString then
    Result.Expand := ExpandOf(TJSONObject(AValue).GetValue<string>('expand', ''))
  else
  begin
    // Server vor #770: "full".
    Full := TJSONObject(AValue).GetValue('full');
    if Full is TJSONBool then
      if TJSONBool(Full).AsBoolean then
        Result.Expand := TAtlasDocExpand.Expanded
      else
        Result.Expand := TAtlasDocExpand.Collapsed;
  end;
  Result.MaxLines := EnsureRange(TJSONObject(AValue).GetValue<Integer>('maxLines', AFallback.MaxLines), 0,
    MaxMaxLines);
end;

{ TAtlasDocParam }

function TAtlasDocParam.TypeText: string;
begin
  Result := Trim(Modifier + ' ' + TypeName);
end;

{ TAtlasDocSignature }

function TAtlasDocSignature.IndexOf(const AName: string): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(Params) do
    if SameText(Params[Index].Name, AName) then
      Exit(Index);
  Result := -1;
end;

function TAtlasDocSignature.HasTypes: Boolean;
var
  Param: TAtlasDocParam;
begin
  for Param in Params do
    if Param.TypeText <> '' then
      Exit(True);
  Result := False;
end;

/// <summary>Stelle von AChar ab AFrom außerhalb von Klammern, spitzen Klammern und Strings; 0 ohne.</summary>
function FindTop(const AText: string; AChar: Char; AFrom: Integer): Integer;
var
  Index, Depth: Integer;
  InString: Boolean;
begin
  Depth := 0;
  InString := False;
  for Index := AFrom to Length(AText) do
  begin
    if AText[Index] = '''' then
      InString := not InString;
    if InString then
      Continue;
    if (Depth = 0) and (AText[Index] = AChar) then
      Exit(Index);
    if CharInSet(AText[Index], ['(', '[', '<']) then
      Inc(Depth)
    else if CharInSet(AText[Index], [')', ']', '>']) and (Depth > 0) then
      Dec(Depth);
  end;
  Result := 0;
end;

/// <summary>Teile von AText an ASeparator außerhalb von Klammern.</summary>
function SplitTop(const AText: string; ASeparator: Char): TArray<string>;
var
  Start, Stop: Integer;
begin
  Result := nil;
  Start := 1;
  repeat
    Stop := FindTop(AText, ASeparator, Start);
    if Stop = 0 then
    begin
      Result := Result + [Trim(Copy(AText, Start, MaxInt))];
      Break;
    end;
    Result := Result + [Trim(Copy(AText, Start, Stop - Start))];
    Start := Stop + 1;
  until False;
end;

class function TAtlasDocSignature.Parse(const ADeclaration: string): TAtlasDocSignature;
const
  Modifiers: array[0..3] of string = ('const', 'var', 'out', 'constref');
  Directives: array[0..6] of string = ('read', 'write', 'index', 'default', 'stored', 'nodefault', 'implements');
var
  Text, Head, Group, Names, TypeName, Modifier, Name, Word, Rest: string;
  Open, Close, Colon, Equal, Index: Integer;
  CloseChar: Char;
  Param: TAtlasDocParam;
begin
  Result := Default(TAtlasDocSignature);
  Text := Trim(StringReplace(StringReplace(ADeclaration, #13, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll]));
  if Text = '' then
    Exit;
  // Erstes Wort nach "class": function, procedure, constructor, destructor, operator, property.
  Head := LowerCase(Text);
  if Head.StartsWith('class ') then
    Head := Trim(Copy(Head, 7, MaxInt));
  Word := Copy(Head, 1, Pos(' ', Head + ' ') - 1);
  if (Word <> 'function') and (Word <> 'procedure') and (Word <> 'constructor') and (Word <> 'destructor') and
    (Word <> 'operator') and (Word <> 'property') then
    Exit;
  // Parameterliste: erste runde (bzw. bei Properties eckige) Klammer nach dem Namen, außerhalb von Generics.
  Result.IsProperty := Word = 'property';
  if Result.IsProperty then
    CloseChar := ']'
  else
    CloseChar := ')';
  Open := 0;
  Index := 1;
  while Index <= Length(Text) do
  begin
    if Text[Index] = '<' then
    begin
      Close := FindTop(Text, '>', Index + 1);
      if Close = 0 then
        Break;
      Index := Close + 1;
      Continue;
    end;
    if CharInSet(Text[Index], [':', ';', '=']) then
      Break;
    if ((CloseChar = ')') and (Text[Index] = '(')) or ((CloseChar = ']') and (Text[Index] = '[')) then
    begin
      Open := Index;
      Break;
    end;
    Inc(Index);
  end;
  Rest := Text;
  if Open > 0 then
  begin
    Close := FindTop(Text, CloseChar, Open + 1);
    if Close = 0 then
      Exit;
    for Group in SplitTop(Copy(Text, Open + 1, Close - Open - 1), ';') do
    begin
      if Group = '' then
        Continue;
      Colon := FindTop(Group, ':', 1);
      if Colon > 0 then
      begin
        Names := Trim(Copy(Group, 1, Colon - 1));
        TypeName := Trim(Copy(Group, Colon + 1, MaxInt));
        Equal := FindTop(TypeName, '=', 1);
        if Equal > 0 then
          TypeName := Trim(Copy(TypeName, 1, Equal - 1));
      end
      else
      begin
        Names := Group;
        TypeName := '';
      end;
      // [Ref] und andere Attribute stehen vor oder nach der Art (const/var/out).
      while Names.StartsWith('[') and (Pos(']', Names) > 0) do
        Names := Trim(Copy(Names, Pos(']', Names) + 1, MaxInt));
      Modifier := '';
      for Word in Modifiers do
        if LowerCase(Names).StartsWith(Word + ' ') then
        begin
          Modifier := Word;
          Names := Trim(Copy(Names, Length(Word) + 1, MaxInt));
          Break;
        end;
      // Attribute zwischen Art und Name ebenfalls weglassen.
      while Names.StartsWith('[') and (Pos(']', Names) > 0) do
        Names := Trim(Copy(Names, Pos(']', Names) + 1, MaxInt));
      for Name in SplitTop(Names, ',') do
        if Name <> '' then
        begin
          Param.Name := Name;
          Param.Modifier := Modifier;
          Param.TypeName := TypeName;
          Result.Params := Result.Params + [Param];
        end;
    end;
    Rest := Copy(Text, Close + 1, MaxInt);
  end
  else
    Rest := Copy(Text, Index, MaxInt);
  Result.Known := True;
  // Ergebnis- bzw. Property-Typ: nach ":" bis ";" oder bis zum ersten Wort von read/write/index/default.
  Rest := Trim(Rest);
  if Rest.StartsWith(':') then
  begin
    Rest := Trim(Copy(Rest, 2, MaxInt));
    Close := FindTop(Rest, ';', 1);
    if Close > 0 then
      Rest := Copy(Rest, 1, Close - 1);
    for Word in Directives do
    begin
      Index := Pos(' ' + Word + ' ', LowerCase(Rest) + ' ');
      if Index > 0 then
        Rest := Copy(Rest, 1, Index - 1);
    end;
    Result.ResultType := Trim(Rest);
  end;
end;

end.
