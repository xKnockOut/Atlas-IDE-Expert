unit Atlas.Core.Hover.Contract;

// Inhalt des Hover-Tooltips (#442, #588) aus dem Objekt "atlas" der Hover-
// Antwort: Deklaration, Unit, Doku (Klartext und seit #654 strukturiert samt
// Anzeige-Einstellungen), Wert, Veraltung, dazu Art und Herkunft für
// die Kopfzeile, Fundort, Typnamen in der Deklaration als Links und die
// Vererbungskette. Ohne "atlas" (fremder Server, Direktiven, Schlüsselwörter)
// wird der Klartext wie bisher in Deklaration und Doku geteilt.
// Bei Komponentenklassen (#110) kommen die published-Properties und Ereignisse
// samt geerbter aus "atlas.published", dazu die Standard-Property.
// Neu zugewiesene Variablen (#712) aus "atlas.reassigned": Art, Zahl der
// Zuweisungen und ihre Zeilen.

interface

uses
  System.JSON,
  Atlas.Core.Documentation.Contract;

type
  /// <summary>Typ mit Fundort (0-basiert); FileName '' ohne Fundort.</summary>
  TAtlasHoverTypeRef = record
    Name: string;
    UnitName: string;
    FileName: string;
    Line: Integer;
    Character: Integer;
    function HasLocation: Boolean;
    /// <summary>Schlüssel für "derselbe Typ" (Datei und Position bzw. Name).</summary>
    function Key: string;
    class function FromJson(const AObject: TJSONObject): TAtlasHoverTypeRef; static;
  end;

  /// <summary>Vorgabe eines published-Mitglieds (#110): keine Angabe, default Wert, implizit (False, 0, erster
  /// Aufzählungswert) bzw. nodefault.</summary>
  TAtlasHoverDefaultKind = (hdNone, hdExplicit, hdImplicit, hdNoDefault);

  /// <summary>published-Property oder Ereignis einer Komponentenklasse (#110).</summary>
  TAtlasHoverMember = record
    Name: string;
    TypeName: string;
    /// <summary>Wert nach default bzw. der implizite Wert; '' ohne.</summary>
    DefaultValue: string;
    DefaultKind: TAtlasHoverDefaultKind;
    /// <summary>Text nach stored (False, IsCaptionStored); '' ohne.</summary>
    Stored: string;
    /// <summary>Klasse, die das Mitglied mit Typ deklariert.</summary>
    DeclaringClass: string;
    IsEvent: Boolean;
    /// <summary>Hat eine Vorgabe (ausdrücklich oder implizit).</summary>
    function HasDefault: Boolean;
    /// <summary>Spalte „Vorgabe“ als Klartext: "crDefault", "False (implizit)", "nodefault", dazu "stored …".
    /// </summary>
    function DefaultText(const AImplicit: string): string;
  end;

  /// <summary>Typname in der Deklaration: Start (0-basiert) und Länge im Text.</summary>
  TAtlasHoverLink = record
    Start: Integer;
    Length: Integer;
    Target: TAtlasHoverTypeRef;
  end;

  TAtlasHoverData = record
  public const
    KindClassRef = 'classref';
    /// <summary>Bis zu so vielen Gliedern zeigt der Tooltip die ganze Kette.</summary>
    MaxChainShown = 5;
    /// <summary>So viele Zeilen nennt ReassignedText.</summary>
    MaxReassignedLines = 5;
  public
    Declaration: string;
    UnitName: string;
    /// <summary>Doku als Klartext (Sprachausgabe, Rückfall ohne Doc).</summary>
    Documentation: string;
    /// <summary>Strukturierte XMLDoc (#654); leer bei fremden Servern.</summary>
    Doc: TAtlasDoc;
    /// <summary>Anzeige laut Server (atlas.xmlDoc); Known = False ohne Angabe.</summary>
    Display: TAtlasDocDisplay;
    Value: string;
    Deprecation: string;
    /// <summary>class, classref, record, interface, enum, type, method … ('' unbekannt).</summary>
    Kind: string;
    /// <summary>VCL, FMX, RTL oder '' (eigene Unit).</summary>
    Origin: string;
    DocWiki: string;
    /// <summary>Fundort der Deklaration; Name ist der deklarierte Name, wenn bekannt.</summary>
    Location: TAtlasHoverTypeRef;
    Links: TArray<TAtlasHoverLink>;
    /// <summary>Typ, dessen Kette Ancestors zeigt (bei "class of T" T).</summary>
    ChainOf: string;
    Ancestors: TArray<TAtlasHoverTypeRef>;
    /// <summary>published-Properties und Ereignisse samt geerbter (#110), abgeleitete Klassen zuerst.</summary>
    Members: TArray<TAtlasHoverMember>;
    /// <summary>Standard-Property (Array-Property mit default), z. B. "Strings[Index: Integer]: string"; '' ohne.
    /// </summary>
    DefaultProperty: string;
    /// <summary>Art des neu zugewiesenen Namens (#712): locals, loopVars, valueParams, varParams, fields; ''
    /// ohne.</summary>
    ReassignedTarget: string;
    ReassignedWrites: Integer;
    /// <summary>Zeilen der Zuweisungen (0-basiert).</summary>
    ReassignedLines: TArray<Integer>;
    function Found: Boolean;
    /// <summary>Zeile „Neu zugewiesen: …“ (#712) mit 1-basierten Zeilen, höchstens MaxReassignedLines, dann
    /// „…“; AOne mit %s für die Zeile, ACount mit %d und %s. '' ohne Angabe.</summary>
    function ReassignedText(const AOne, ACount: string): string;
    /// <summary>Angabe verwerfen (Einstellung aus oder Art nicht gewählt).</summary>
    procedure ClearReassigned;
    /// <summary>Zahl der published-Properties bzw. -Ereignisse (#110).</summary>
    function MemberCount(AEvents: Boolean): Integer;
    /// <summary>Indizes in Members: Properties oder Ereignisse; ohne AInherited nur die der Klasse selbst
    /// (DeclaringClass = Title), mit AOnlyDefaults nur Properties mit Vorgabe.</summary>
    function VisibleMembers(AEvents, AInherited, AOnlyDefaults: Boolean): TArray<Integer>;
    /// <summary>Liste für die Zwischenablage (#110): Titel, dann je Zeile Name, Typ, Vorgabe und deklarierende
    /// Klasse durch Tabulatoren getrennt; erst Properties, dann Ereignisse, gefiltert wie VisibleMembers.
    /// AImplicit ist das Wort für „implizit“.</summary>
    function MembersText(AInherited, AOnlyDefaults: Boolean; const AImplicit: string): string;
    /// <summary>Name des angezeigten Typs: erstes Kettenglied bzw. Name am Fundort bzw. Deklarationsanfang.</summary>
    function Title: string;
    /// <summary>Kürzel für das Badge wie in der Vervollständigung (ty, fn, pp, fd, va, co, un, kw).</summary>
    function Badge: string;
    /// <summary>"Datei.pas : 20" (1-basiert) bzw. die Unit; '' ohne beides.</summary>
    function LocationText: string;
    /// <summary>Indizes der anzuzeigenden Kettenglieder; -1 steht für "…" (mehr als MaxChainShown).</summary>
    function VisibleChain: TArray<Integer>;
    /// <summary>Index des Links an der Textstelle AIndex (0-basiert); -1 ohne.</summary>
    function LinkAt(AIndex: Integer): Integer;
    class function FromHover(const AHover: TJSONValue): TAtlasHoverData; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.SysUtils,
  System.StrUtils,
  System.Math;

{ TAtlasHoverTypeRef }

function TAtlasHoverTypeRef.HasLocation: Boolean;
begin
  Result := FileName <> '';
end;

function TAtlasHoverTypeRef.Key: string;
begin
  if HasLocation then
    Result := Format('%s|%d|%d', [UpperCase(FileName), Line, Character])
  else
    Result := UpperCase(Name);
end;

class function TAtlasHoverTypeRef.FromJson(const AObject: TJSONObject): TAtlasHoverTypeRef;
begin
  Result := Default(TAtlasHoverTypeRef);
  if AObject = nil then
    Exit;
  Result.Name := AObject.GetValue<string>('name', '');
  Result.UnitName := AObject.GetValue<string>('unit', '');
  Result.FileName := AObject.GetValue<string>('file', '');
  Result.Line := AObject.GetValue<Integer>('line', 0);
  Result.Character := AObject.GetValue<Integer>('character', 0);
end;

{ TAtlasHoverMember }

function TAtlasHoverMember.HasDefault: Boolean;
begin
  Result := (DefaultKind = hdExplicit) or (DefaultKind = hdImplicit);
end;

function TAtlasHoverMember.DefaultText(const AImplicit: string): string;
begin
  case DefaultKind of
    hdExplicit: Result := DefaultValue;
    hdImplicit: Result := DefaultValue + ' (' + AImplicit + ')';
    hdNoDefault: Result := 'nodefault';
  else
    Result := '';
  end;
  if Stored <> '' then
    Result := Trim(Result + ' stored ' + Stored);
end;

{ TAtlasHoverData }

function TAtlasHoverData.Found: Boolean;
begin
  Result := Declaration <> '';
end;

function TAtlasHoverData.ReassignedText(const AOne, ACount: string): string;
var
  Index: Integer;
  Lines: string;
begin
  Result := '';
  if (ReassignedTarget = '') or (ReassignedWrites <= 0) then
    Exit;
  Lines := '';
  for Index := 0 to Min(High(ReassignedLines), MaxReassignedLines - 1) do
  begin
    if Lines <> '' then
      Lines := Lines + ', ';
    Lines := Lines + IntToStr(ReassignedLines[Index] + 1);
  end;
  if Length(ReassignedLines) > MaxReassignedLines then
    Lines := Lines + ', …';
  if ReassignedWrites = 1 then
    Result := Format(AOne, [Lines])
  else
    Result := Format(ACount, [ReassignedWrites, Lines]);
end;

procedure TAtlasHoverData.ClearReassigned;
begin
  ReassignedTarget := '';
  ReassignedWrites := 0;
  ReassignedLines := nil;
end;

function TAtlasHoverData.MemberCount(AEvents: Boolean): Integer;
var
  Member: TAtlasHoverMember;
begin
  Result := 0;
  for Member in Members do
    if Member.IsEvent = AEvents then
      Inc(Result);
end;

function TAtlasHoverData.VisibleMembers(AEvents, AInherited, AOnlyDefaults: Boolean): TArray<Integer>;
var
  Index: Integer;
  Own: string;
begin
  Result := nil;
  Own := Title;
  for Index := 0 to High(Members) do
    if (Members[Index].IsEvent = AEvents) and (AInherited or SameText(Members[Index].DeclaringClass, Own)) and
      (AEvents or not AOnlyDefaults or Members[Index].HasDefault) then
      Result := Result + [Index];
end;

function TAtlasHoverData.MembersText(AInherited, AOnlyDefaults: Boolean; const AImplicit: string): string;
var
  Index, Pass: Integer;
  Member: TAtlasHoverMember;
begin
  Result := Title;
  // Erst Properties, dann Ereignisse.
  for Pass := 0 to 1 do
    for Index in VisibleMembers(Pass = 1, AInherited, AOnlyDefaults) do
    begin
      Member := Members[Index];
      Result := Result + sLineBreak + Member.Name + #9 + Member.TypeName + #9 + Member.DefaultText(AImplicit) + #9 +
        Member.DeclaringClass;
    end;
  if DefaultProperty <> '' then
    Result := Result + sLineBreak + DefaultProperty + #9 + 'default';
end;

function TAtlasHoverData.Title: string;
var
  Index: Integer;
begin
  if (Length(Ancestors) > 0) and (Kind <> KindClassRef) then
    Exit(Ancestors[0].Name);
  if Location.Name <> '' then
    Exit(Location.Name);
  // Erster Bezeichner der Deklaration (TFoo = class, Name: Typ, procedure Bar).
  Result := Trim(Declaration);
  for Index := 1 to Length(Result) do
    if not CharInSet(Result[Index], ['A'..'Z', 'a'..'z', '0'..'9', '_', '.', '&']) then
    begin
      Result := Copy(Result, 1, Index - 1);
      Break;
    end;
  if MatchText(Result, ['procedure', 'function', 'constructor', 'destructor', 'property', 'class', 'type',
    'var', 'const']) then
  begin
    Result := Trim(Copy(Trim(Declaration), Length(Result) + 1, MaxInt));
    for Index := 1 to Length(Result) do
      if not CharInSet(Result[Index], ['A'..'Z', 'a'..'z', '0'..'9', '_', '.', '&']) then
      begin
        Result := Copy(Result, 1, Index - 1);
        Break;
      end;
  end;
end;

function TAtlasHoverData.Badge: string;
begin
  if MatchStr(Kind, ['class', 'classref', 'object', 'record', 'interface', 'helper', 'enum', 'type']) then
    Result := 'ty'
  else if MatchStr(Kind, ['method', 'constructor', 'routine']) then
    Result := 'fn'
  else if Kind = 'property' then
    Result := 'pp'
  else if Kind = 'field' then
    Result := 'fd'
  else if Kind = 'variable' then
    Result := 'va'
  else if MatchStr(Kind, ['constant', 'enumMember']) then
    Result := 'co'
  else if StartsText('unit ', Declaration) then
    Result := 'un'
  else
    Result := 'kw';
end;

function TAtlasHoverData.LocationText: string;
begin
  if Location.HasLocation then
    Result := Format('%s : %d', [ExtractFileName(Location.FileName), Location.Line + 1])
  else
    Result := UnitName;
end;

function TAtlasHoverData.VisibleChain: TArray<Integer>;
var
  Index: Integer;
begin
  Result := nil;
  if Length(Ancestors) <= MaxChainShown then
  begin
    for Index := 0 to High(Ancestors) do
      Result := Result + [Index];
    Exit;
  end;
  // Die ersten vier, dann "…", dann das letzte (meist TObject).
  for Index := 0 to MaxChainShown - 2 do
    Result := Result + [Index];
  Result := Result + [-1, High(Ancestors)];
end;

function TAtlasHoverData.LinkAt(AIndex: Integer): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(Links) do
    if (AIndex >= Links[Index].Start) and (AIndex < Links[Index].Start + Links[Index].Length) then
      Exit(Index);
  Result := -1;
end;

function PlainText(const AHover: TJSONValue): string;
var
  Contents: TJSONValue;
begin
  Result := '';
  if not (AHover is TJSONObject) then
    Exit;
  Contents := TJSONObject(AHover).GetValue('contents');
  if Contents is TJSONString then
    Result := Contents.Value
  else if Contents is TJSONObject then
    Result := TJSONObject(Contents).GetValue<string>('value', '');
end;

function MemberFromJson(AObject: TJSONObject): TAtlasHoverMember;
var
  Kind: string;
begin
  Result := Default(TAtlasHoverMember);
  Result.Name := AObject.GetValue<string>('name', '');
  Result.TypeName := AObject.GetValue<string>('type', '');
  Result.DefaultValue := AObject.GetValue<string>('default', '');
  Kind := AObject.GetValue<string>('defaultKind', '');
  if Kind = 'explicit' then
    Result.DefaultKind := hdExplicit
  else if Kind = 'implicit' then
    Result.DefaultKind := hdImplicit
  else if Kind = 'nodefault' then
    Result.DefaultKind := hdNoDefault;
  Result.Stored := AObject.GetValue<string>('stored', '');
  Result.DeclaringClass := AObject.GetValue<string>('declaringClass', '');
  Result.IsEvent := AObject.GetValue<Boolean>('event', False);
end;

class function TAtlasHoverData.FromHover(const AHover: TJSONValue): TAtlasHoverData;
var
  Atlas, Item: TJSONObject;
  List: TJSONArray;
  Value: TJSONValue;
  Link: TAtlasHoverLink;
  Text: string;
  Split: Integer;
begin
  Result := Default(TAtlasHoverData);
  if not (AHover is TJSONObject) then
    Exit;
  Atlas := TJSONObject(AHover).GetValue('atlas') as TJSONObject;
  if Atlas = nil then
  begin
    // Rückfall: erster Absatz Deklaration, der Rest Doku; Markdown-Zäune entfernen.
    Text := StringReplace(PlainText(AHover), '```pascal', '', [rfReplaceAll]);
    Text := Trim(StringReplace(Text, '```', '', [rfReplaceAll]));
    Split := Pos(#10#10, Text);
    if Split = 0 then
      Result.Declaration := Text
    else
    begin
      Result.Declaration := Trim(Copy(Text, 1, Split - 1));
      Result.Documentation := Trim(Copy(Text, Split + 2, MaxInt));
    end;
    Exit;
  end;
  Result.Declaration := Atlas.GetValue<string>('declaration', '');
  Result.UnitName := Atlas.GetValue<string>('unit', '');
  // Seit #654 ist "documentation" strukturiert, der Klartext steht in "documentationText".
  if not Atlas.TryGetValue<string>('documentationText', Result.Documentation) and
    (Atlas.GetValue('documentation') is TJSONString) then
    Result.Documentation := Atlas.GetValue('documentation').Value;
  Result.Doc := TAtlasDoc.FromJson(Atlas.GetValue('documentation'));
  // Nur Begründungen (#1123) strukturiert: die Doku als Klartext davor, sonst fiele sie weg.
  if (Result.Documentation <> '') and not Result.Doc.IsEmpty and
    (Length(Result.Doc.Sections) = Length(Result.Doc.SectionsOf(TAtlasDocSectionKind.Rationale))) then
    Result.Doc.Sections := TAtlasDoc.FromText(Result.Documentation).Sections + Result.Doc.Sections;
  Result.Display := TAtlasDocDisplay.FromJson(Atlas.GetValue('xmlDoc'),
    TAtlasDocDisplay.Create(TAtlasDocExpand.Last, 0));
  Result.Value := Atlas.GetValue<string>('value', '');
  Result.Deprecation := Atlas.GetValue<string>('deprecation', '');
  Result.Kind := Atlas.GetValue<string>('kind', '');
  Result.Origin := Atlas.GetValue<string>('origin', '');
  Result.DocWiki := Atlas.GetValue<string>('docWiki', '');
  Result.Location := TAtlasHoverTypeRef.FromJson(Atlas);
  Result.Location.Name := '';
  Result.Location.UnitName := Result.UnitName;
  Result.ChainOf := Atlas.GetValue<string>('chainOf', '');
  if Atlas.TryGetValue<TJSONArray>('links', List) then
    for Value in List do
      if Value is TJSONObject then
      begin
        Item := TJSONObject(Value);
        Link.Start := Item.GetValue<Integer>('start', 0);
        Link.Length := Item.GetValue<Integer>('length', 0);
        Link.Target := TAtlasHoverTypeRef.FromJson(Item);
        if Link.Length > 0 then
          Result.Links := Result.Links + [Link];
      end;
  if Atlas.TryGetValue<TJSONArray>('ancestors', List) then
    for Value in List do
      if Value is TJSONObject then
        Result.Ancestors := Result.Ancestors + [TAtlasHoverTypeRef.FromJson(TJSONObject(Value))];
  // published-Properties und Ereignisse (#110).
  if Atlas.TryGetValue<TJSONObject>('published', Item) then
  begin
    Result.DefaultProperty := Item.GetValue<string>('defaultProperty', '');
    if Item.TryGetValue<TJSONArray>('members', List) then
      for Value in List do
        if Value is TJSONObject then
          Result.Members := Result.Members + [MemberFromJson(TJSONObject(Value))];
  end;
  // Neu zugewiesene Variablen (#712).
  if Atlas.TryGetValue<TJSONObject>('reassigned', Item) then
  begin
    Result.ReassignedTarget := Item.GetValue<string>('target', '');
    Result.ReassignedWrites := Item.GetValue<Integer>('writes', 0);
    if Item.TryGetValue<TJSONArray>('lines', List) then
      for Value in List do
        if Value is TJSONNumber then
          Result.ReassignedLines := Result.ReassignedLines + [TJSONNumber(Value).AsInt];
  end;
  // Der angezeigte Typ selbst: erstes Kettenglied mit demselben Fundort.
  if (Length(Result.Ancestors) > 0) and (Result.Ancestors[0].Key = Result.Location.Key) then
    Result.Location.Name := Result.Ancestors[0].Name;
end;

end.
