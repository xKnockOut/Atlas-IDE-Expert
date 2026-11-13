unit Atlas.Text.Xml;

// Kleiner XML-Leser für Berichte fremder Werkzeuge, gemeinsam für Server und
// Plugin: DUnitX-Berichte (Atlas.Text.TestResults, #69) und Berichte der
// Testabdeckung (Atlas.Text.Coverage, #275). Kein DOM: Der Cursor liefert
// Start-, End- und Textknoten nacheinander, mit Attributen; Entitäten
// werden entschlüsselt, CDATA bleibt wörtlich, Kommentare, Deklarationen und
// Verarbeitungsanweisungen werden übersprungen. Namensräume, DTDs und
// Prüfung auf Wohlgeformtheit gibt es nicht.

interface

uses
  System.SysUtils;

{$SCOPEDENUMS ON}

type
  TXmlNodeKind = (StartTag, EndTag, Text, Done);
  // Ergebnis von SkipDeclaration: nichts übersprungen, übersprungen, ohne Ende.
  TXmlSkip = (None, Skipped, Unclosed);

  /// <summary>Kleiner Leser, der ein XML-Dokument Knoten für Knoten durchläuft (Start-, End- und Textknoten).
  /// </summary>
  TXmlCursor = record
    Source: string;
    Position: Integer;
    Kind: TXmlNodeKind;
    Name: string;
    /// <summary>Text eines Textknotens (entschlüsselt, CDATA wörtlich).</summary>
    Value: string;
    SelfClosing: Boolean;
    AttributeNames: TArray<string>;
    AttributeValues: TArray<string>;
    /// <summary>Beginnt am Anfang von AText.</summary>
    procedure Init(const AText: string);
    /// <summary>Nächster Knoten in Kind, Name, Value und den Attributen; False am Ende.</summary>
    function Next: Boolean;
    /// <summary>Wert des Attributs AName des aktuellen Starttags (Groß-/Kleinschreibung egal); '' ohne.</summary>
    function Attribute(const AName: string): string;
    /// <summary>Steht an Position ein Zeichen aus AChars?</summary>
    function CharIs(const AChars: TSysCharSet): Boolean;
    procedure SkipWhile(const AChars: TSysCharSet);
    /// <summary>Text ab Position bis vor das erste Zeichen aus AStops (oder bis zum Ende).</summary>
    function TakeUntil(const AStops: TSysCharSet): string;
    function SkipPast(const AClose: string; AFrom: Integer): TXmlSkip;
    /// <summary>Kommentar, Verarbeitungsanweisung oder Deklaration ab Position überspringen.</summary>
    function SkipDeclaration: TXmlSkip;
    procedure ReadCData;
    procedure ReadAttribute;
    procedure ReadTag;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Text.Entities;

const
  cXmlSpaces = [' ', #9, #13, #10];
  cCommentOpen = '<!--';
  cCommentClose = '-->';
  cCDataOpen = '<![CDATA[';
  cCDataClose = ']]>';

procedure TXmlCursor.Init(const AText: string);
begin
  Source := AText;
  Position := 1;
  Kind := TXmlNodeKind.Done;
end;

function TXmlCursor.Attribute(const AName: string): string;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AttributeNames) do
  begin
    if SameText(AttributeNames[mIndex], AName) then
    begin
      Exit(AttributeValues[mIndex]);
    end;
  end;
  Result := '';
end;

function TXmlCursor.CharIs(const AChars: TSysCharSet): Boolean;
begin
  Result := (Position <= Length(Source)) and CharInSet(Source[Position], AChars);
end;

procedure TXmlCursor.SkipWhile(const AChars: TSysCharSet);
begin
  while CharIs(AChars) do
  begin
    Inc(Position);
  end;
end;

function TXmlCursor.TakeUntil(const AStops: TSysCharSet): string;
var
  mStart: Integer;
begin
  mStart := Position;
  while (Position <= Length(Source)) and not CharInSet(Source[Position], AStops) do
  begin
    Inc(Position);
  end;
  Result := Copy(Source, mStart, Position - mStart);
end;

function TXmlCursor.SkipPast(const AClose: string; AFrom: Integer): TXmlSkip;
var
  mStop: Integer;
begin
  mStop := PosEx(AClose, Source, AFrom);
  if mStop = 0 then
  begin
    Exit(TXmlSkip.Unclosed);
  end;
  Position := mStop + Length(AClose);
  Result := TXmlSkip.Skipped;
end;

function TXmlCursor.SkipDeclaration: TXmlSkip;
begin
  if Copy(Source, Position, Length(cCommentOpen)) = cCommentOpen then
  begin
    Exit(SkipPast(cCommentClose, Position + Length(cCommentOpen)));
  end;
  Result := TXmlSkip.None;
  if (Copy(Source, Position, 2) = '<?') or (Copy(Source, Position, 2) = '<!') then
  begin
    Result := SkipPast('>', Position + 2);
  end;
end;

procedure TXmlCursor.ReadCData;
var
  mStart, mStop: Integer;
begin
  mStart := Position + Length(cCDataOpen);
  mStop := PosEx(cCDataClose, Source, mStart);
  if mStop = 0 then
  begin
    mStop := Length(Source) + 1;
  end;
  Kind := TXmlNodeKind.Text;
  Value := Copy(Source, mStart, mStop - mStart);
  Position := mStop + Length(cCDataClose);
end;

procedure TXmlCursor.ReadAttribute;
var
  mName: string;
  mQuote: Char;
begin
  mName := TakeUntil(['=', ' ', #9, #13, #10, '>', '/']);
  SkipWhile(cXmlSpaces);
  if not CharIs(['=']) then
  begin
    Exit;
  end;
  Inc(Position);
  SkipWhile(cXmlSpaces);
  if not CharIs(['"', '''']) then
  begin
    Exit;
  end;
  mQuote := Source[Position];
  Inc(Position);
  AttributeNames := AttributeNames + [mName];
  AttributeValues := AttributeValues + [TTextEntities.Decode(TakeUntil([mQuote]))];
  Inc(Position);
end;

procedure TXmlCursor.ReadTag;
begin
  Inc(Position);
  Kind := TXmlNodeKind.StartTag;
  if CharIs(['/']) then
  begin
    Kind := TXmlNodeKind.EndTag;
    Inc(Position);
  end;
  Name := TakeUntil([' ', #9, #13, #10, '/', '>']);
  while Position <= Length(Source) do
  begin
    case Source[Position] of
      '>':
        begin
          Inc(Position);
          Exit;
        end;
      '/':
        begin
          SelfClosing := True;
          Inc(Position);
        end;
      ' ', #9, #13, #10:
        Inc(Position);
    else
      ReadAttribute;
    end;
  end;
end;

function TXmlCursor.Next: Boolean;
begin
  Name := '';
  Value := '';
  SelfClosing := False;
  AttributeNames := nil;
  AttributeValues := nil;
  Result := True;
  while Position <= Length(Source) do
  begin
    if Source[Position] <> '<' then
    begin
      Kind := TXmlNodeKind.Text;
      Value := TTextEntities.Decode(TakeUntil(['<']));
      Exit;
    end;
    if Copy(Source, Position, Length(cCDataOpen)) = cCDataOpen then
    begin
      ReadCData;
      Exit;
    end;
    case SkipDeclaration of
      TXmlSkip.Skipped:
        Continue;
      TXmlSkip.Unclosed:
        Break;
      TXmlSkip.None: ;
    end;
    ReadTag;
    Exit;
  end;
  Kind := TXmlNodeKind.Done;
  Result := False;
end;

end.
