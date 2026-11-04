unit Atlas.Core.EditorToolbar.Sections;

// Atlas-Editorleiste (#1101), Abschnittssprünge ohne VCL und OTA: Scan liest
// den Editortext direkt (ohne Server, auch bei Syntaxfehlern) und findet die
// Schlüsselwörter auf Unit-Ebene.
// - Kommentare ({ }, (* *), //), Direktiven ({$ }, (*$ *)), Strings ('…' mit
//   '' darin) und mehrzeilige Strings (''' bis ''') zählen nicht; ebenso
//   Bezeichner mit & davor (&interface).
// - interface: das erste Wort nach dem Unit-Kopf (unit Name;). Fehlt der Kopf
//   oder ist er kaputt, das erste interface, vor dem kein „=“ steht; so zählt
//   IFoo = interface nie.
// - implementation, initialization und finalization sind reservierte Wörter
//   und stehen nur auf Unit-Ebene; uses gehört zum Abschnitt, in dem es steht.
// - Programm, Bibliothek und Package haben weder interface noch
//   implementation; ihre uses-Klausel (beim Package contains) ist der Sprung
//   „Zur uses-Klausel“. Eine Datei ohne Kopf (.inc) hat keine Abschnitte.
// - end. beendet die Suche.
// SectionAt nennt den Abschnitt an einer Stelle für die Hervorhebung der
// Knöpfe; Target das Sprungziel, bei uses die Klausel des aktuellen
// Abschnitts (ohne eigene die des interface).

interface

uses
  System.SysUtils,
  Atlas.Core.Outline.Breadcrumbs;

type
{$SCOPEDENUMS ON}
  TAtlasSourceKind = (Unit_, Program_, Library_, Package, Include);
  /// <summary>Sprungziele der Editorleiste.</summary>
  TAtlasSectionTarget = (InterfacePart, ImplementationPart, UsesClause, Initialization_);
{$SCOPEDENUMS OFF}

  /// <summary>Stelle eines Schlüsselworts, 0-basiert; Found = False, wenn es fehlt.</summary>
  TAtlasSectionMark = record
    Found: Boolean;
    Line: Integer;
    Character: Integer;
    class function At(ALine, ACharacter: Integer): TAtlasSectionMark; static;
    /// <summary>Liegt die Stelle ALine/ACharacter an oder hinter dieser Marke?</summary>
    function Before(ALine, ACharacter: Integer): Boolean;
  end;

  /// <summary>uses-Klausel: Schlüsselwort und abschließendes Semikolon (ohne Semikolon bis zum Dateiende).</summary>
  TAtlasUsesMark = record
    Start: TAtlasSectionMark;
    Stop: TAtlasSectionMark;
    function Contains(ALine, ACharacter: Integer): Boolean;
  end;

  TAtlasUnitSections = record
    Kind: TAtlasSourceKind;
    InterfacePart: TAtlasSectionMark;
    ImplementationPart: TAtlasSectionMark;
    Initialization_: TAtlasSectionMark;
    Finalization_: TAtlasSectionMark;
    /// <summary>uses-Klausel nach dem Kopf eines Programms bzw. contains eines Packages.</summary>
    HeaderUses: TAtlasUsesMark;
    InterfaceUses: TAtlasUsesMark;
    ImplementationUses: TAtlasUsesMark;
    /// <summary>Hat die Datei interface- und implementation-Teil (nur Units)?</summary>
    function HasParts: Boolean;
    /// <summary>Abschnitt an der Stelle (0-basiert) für die Hervorhebung.</summary>
    function SectionAt(ALine, ACharacter: Integer): TAtlasCodeSection;
    /// <summary>Sprungziel von der Stelle ALine/ACharacter aus; False, wenn die Datei es nicht hat.</summary>
    function Target(ATarget: TAtlasSectionTarget; ALine, ACharacter: Integer; out AMark: TAtlasSectionMark): Boolean;
  end;

  TAtlasSectionScanner = class
  public
    /// <summary>Abschnitte aus den Zeilen des Editors.</summary>
    class function Scan(const ALines: TArray<string>): TAtlasUnitSections; overload; static;
    /// <summary>Wie oben aus dem ganzen Text; CR, LF und CRLF trennen die Zeilen.</summary>
    class function Scan(const AText: string): TAtlasUnitSections; overload; static;
  end;

implementation

uses
  Atlas.Text.Chars,
  Atlas.Text.Lines;

{ TAtlasSectionMark }

class function TAtlasSectionMark.At(ALine, ACharacter: Integer): TAtlasSectionMark;
begin
  Result.Found := True;
  Result.Line := ALine;
  Result.Character := ACharacter;
end;

function TAtlasSectionMark.Before(ALine, ACharacter: Integer): Boolean;
begin
  Result := Found and ((Line < ALine) or ((Line = ALine) and (Character <= ACharacter)));
end;

{ TAtlasUsesMark }

function TAtlasUsesMark.Contains(ALine, ACharacter: Integer): Boolean;
begin
  Result := Start.Before(ALine, ACharacter) and (not Stop.Found or (ALine < Stop.Line) or
    ((ALine = Stop.Line) and (ACharacter <= Stop.Character)));
end;

{ TAtlasUnitSections }

function TAtlasUnitSections.HasParts: Boolean;
begin
  Result := (Kind = TAtlasSourceKind.Unit_) and (InterfacePart.Found or ImplementationPart.Found);
end;

function TAtlasUnitSections.SectionAt(ALine, ACharacter: Integer): TAtlasCodeSection;
begin
  if HeaderUses.Contains(ALine, ACharacter) or InterfaceUses.Contains(ALine, ACharacter) or
    ImplementationUses.Contains(ALine, ACharacter) then
  begin
    Result := TAtlasCodeSection.UsesClause;
  end
  else if Finalization_.Before(ALine, ACharacter) then
  begin
    Result := TAtlasCodeSection.Finalization_;
  end
  else if Initialization_.Before(ALine, ACharacter) then
  begin
    Result := TAtlasCodeSection.Initialization_;
  end
  else if ImplementationPart.Before(ALine, ACharacter) then
  begin
    Result := TAtlasCodeSection.ImplementationPart;
  end
  else if InterfacePart.Before(ALine, ACharacter) then
  begin
    Result := TAtlasCodeSection.InterfacePart;
  end
  else
  begin
    Result := TAtlasCodeSection.None;
  end;
end;

function TAtlasUnitSections.Target(ATarget: TAtlasSectionTarget; ALine, ACharacter: Integer;
  out AMark: TAtlasSectionMark): Boolean;
begin
  AMark := Default(TAtlasSectionMark);
  case ATarget of
    TAtlasSectionTarget.InterfacePart:
      AMark := InterfacePart;
    TAtlasSectionTarget.ImplementationPart:
      AMark := ImplementationPart;
    TAtlasSectionTarget.Initialization_:
      AMark := Initialization_;
    TAtlasSectionTarget.UsesClause:
      if Kind <> TAtlasSourceKind.Unit_ then
      begin
        AMark := HeaderUses.Start;
      end
      else if ImplementationPart.Before(ALine, ACharacter) and ImplementationUses.Start.Found then
      begin
        AMark := ImplementationUses.Start;
      end
      else if InterfaceUses.Start.Found then
      begin
        AMark := InterfaceUses.Start;
      end
      else
      begin
        AMark := ImplementationUses.Start;
      end;
  end;
  // Programme, Packages und Include-Dateien haben keine Abschnitte, auch wenn darin ein Wort so heißt.
  if (Kind <> TAtlasSourceKind.Unit_) and (ATarget <> TAtlasSectionTarget.UsesClause) then
  begin
    AMark := Default(TAtlasSectionMark);
  end;
  Result := AMark.Found;
end;

{ TAtlasSectionScanner }

type
  /// <summary>Wort (klein) bzw. „;“, „=“, „.“ oder „&amp;“ und seine Stelle, 0-basiert.</summary>
  TSectionToken = record
    Text: string;
    Line: Integer;
    Character: Integer;
    function Mark: TAtlasSectionMark;
  end;

  /// <summary>Liest Wörter und die Zeichen „;“, „=“ und „.“ außerhalb von Kommentaren und Strings.</summary>
  TTokenReader = record
    Lines: TArray<string>;
    Line: Integer;
    Position: Integer;
    /// <summary>Offener Kommentar über Zeilen: '{' oder '(' für (* *); #0 = keiner.</summary>
    Comment: Char;
    /// <summary>Anzahl der Anführungszeichen eines offenen mehrzeiligen Strings; 0 = keiner.</summary>
    MultiQuotes: Integer;
    /// <summary>Nächstes Wort (klein) bzw. „;“, „=“ oder „.“; False am Ende des Textes.</summary>
    function Next(out AToken: TSectionToken): Boolean;
  private
    /// <summary>Ende eines mehrzeiligen Strings suchen; False, wenn die Zeile noch dazugehört.</summary>
    function LeaveMultiLine(const AText: string): Boolean;
    /// <summary>Ein Zeichen im offenen Kommentar weiter.</summary>
    procedure SkipInComment(const AText: string);
    /// <summary>Kommentar, der bei Position beginnt, öffnen bzw. überspringen; sonst ein Zeichen weiter.</summary>
    procedure OpenComment(const AText: string);
    /// <summary>String ab Position überspringen; ''' am Zeilenende öffnet einen mehrzeiligen.</summary>
    procedure SkipString(const AText: string);
    /// <summary>Token ab Position oder ein Zeichen weiter; False ohne Token.</summary>
    function TokenAt(const AText: string; out AToken: TSectionToken): Boolean;
    function Emit(const AText: string; AStart: Integer; out AToken: TSectionToken): Boolean;
  end;

  /// <summary>Zustand von Scan: Kopf gelesen, offene uses-Klausel, vorheriges Token.</summary>
  TSectionScan = record
    Sections: TAtlasUnitSections;
    HeaderDone: Boolean;
    AfterHeader: Boolean;
    OpenUses: ^TAtlasUsesMark;
    Previous: string;
    /// <summary>Art aus dem ersten Wort; False ohne Kopf (.inc).</summary>
    function TakeKind(const AToken: string): Boolean;
    procedure UnitToken(const AToken: TSectionToken);
    /// <summary>interface oder implementation.</summary>
    procedure FrontPart(const AToken: TSectionToken);
    /// <summary>initialization oder finalization nach implementation.</summary>
    procedure BackPart(const AToken: TSectionToken);
    procedure UnitUses;
    procedure HeaderToken(const AToken: TSectionToken);
    /// <summary>Ein Token nach dem ersten; False nach „end.“.</summary>
    function Take(const AToken: TSectionToken): Boolean;
  end;

function TSectionToken.Mark: TAtlasSectionMark;
begin
  Result := TAtlasSectionMark.At(Line, Character);
end;

/// <summary>Anzahl gleicher Anführungszeichen ab APosition.</summary>
function QuoteRun(const AText: string; APosition: Integer): Integer;
begin
  Result := 0;
  while (APosition + Result <= Length(AText)) and (AText[APosition + Result] = '''') do
  begin
    Inc(Result);
  end;
end;

function TTokenReader.LeaveMultiLine(const AText: string): Boolean;
var
  mStart: Integer;
begin
  Result := True;
  if MultiQuotes = 0 then
  begin
    Exit;
  end;
  // Mehrzeiliger String: endet an einer Zeile, die (nach Einrückung) mit gleich vielen ''' beginnt.
  mStart := 1;
  while (mStart <= Length(AText)) and CharInSet(AText[mStart], [' ', #9]) do
  begin
    Inc(mStart);
  end;
  Result := QuoteRun(AText, mStart) >= MultiQuotes;
  if Result then
  begin
    Position := mStart + MultiQuotes;
    MultiQuotes := 0;
  end;
end;

procedure TTokenReader.SkipInComment(const AText: string);
begin
  if (Comment = '{') and (AText[Position] = '}') then
  begin
    Comment := #0;
  end
  else if (Comment = '(') and (AText[Position] = '*') and (Position < Length(AText)) and
    (AText[Position + 1] = ')') then
  begin
    Comment := #0;
    Inc(Position);
  end;
  Inc(Position);
end;

procedure TTokenReader.OpenComment(const AText: string);
var
  mNext: Char;
begin
  mNext := #0;
  if Position < Length(AText) then
  begin
    mNext := AText[Position + 1];
  end;
  if AText[Position] = '{' then
  begin
    Comment := '{';
    Inc(Position);
  end
  else if (AText[Position] = '(') and (mNext = '*') then
  begin
    Comment := '(';
    Inc(Position, 2);
  end
  else if (AText[Position] = '/') and (mNext = '/') then
  begin
    Position := Length(AText) + 1;
  end
  else
  begin
    Inc(Position);
  end;
end;

procedure TTokenReader.SkipString(const AText: string);
var
  mRun: Integer;
begin
  mRun := QuoteRun(AText, Position);
  // ''' (oder mehr, ungerade) am Zeilenende öffnet einen mehrzeiligen String (Delphi 12).
  if (mRun >= 3) and Odd(mRun) and (Trim(Copy(AText, Position + mRun, MaxInt)) = '') then
  begin
    MultiQuotes := mRun;
    Position := Length(AText) + 1;
    Exit;
  end;
  // Gewöhnlicher String: '' ist ein Anführungszeichen darin.
  Inc(Position);
  while Position <= Length(AText) do
  begin
    if AText[Position] <> '''' then
    begin
      Inc(Position);
    end
    else if (Position < Length(AText)) and (AText[Position + 1] = '''') then
    begin
      Inc(Position, 2);
    end
    else
    begin
      Inc(Position);
      Exit;
    end;
  end;
end;

function TTokenReader.Emit(const AText: string; AStart: Integer; out AToken: TSectionToken): Boolean;
begin
  AToken.Text := AText;
  AToken.Line := Line;
  AToken.Character := AStart - 1;
  Result := True;
end;

function TTokenReader.TokenAt(const AText: string; out AToken: TSectionToken): Boolean;
var
  mStart: Integer;
begin
  Result := False;
  mStart := Position;
  case AText[Position] of
    '{', '(', '/':
      OpenComment(AText);
    '''':
      SkipString(AText);
    ';', '=', '.':
      begin
        Inc(Position);
        Result := Emit(AText[mStart], mStart, AToken);
      end;
    '&':
      begin
        // &interface ist ein Bezeichner, kein Schlüsselwort.
        Inc(Position);
        Result := (Position <= Length(AText)) and TTextChars.IsIdentStart(AText[Position]);
        while (Position <= Length(AText)) and TTextChars.IsIdentChar(AText[Position]) do
        begin
          Inc(Position);
        end;
        if Result then
        begin
          Emit('&', Position, AToken);
        end;
      end;
  else
    if not TTextChars.IsIdentStart(AText[Position]) then
    begin
      Inc(Position);
      Exit;
    end;
    while (Position <= Length(AText)) and TTextChars.IsIdentChar(AText[Position]) do
    begin
      Inc(Position);
    end;
    Result := Emit(LowerCase(Copy(AText, mStart, Position - mStart)), mStart, AToken);
  end;
end;

function TTokenReader.Next(out AToken: TSectionToken): Boolean;
var
  mText: string;
begin
  AToken := Default(TSectionToken);
  while Line <= High(Lines) do
  begin
    mText := Lines[Line];
    if LeaveMultiLine(mText) then
    begin
      while Position <= Length(mText) do
      begin
        if Comment <> #0 then
        begin
          SkipInComment(mText);
        end
        else if TokenAt(mText, AToken) then
        begin
          Exit(True);
        end;
      end;
    end;
    Inc(Line);
    Position := 1;
  end;
  Result := False;
end;

function TSectionScan.TakeKind(const AToken: string): Boolean;
begin
  Result := True;
  if AToken = 'unit' then
  begin
    Sections.Kind := TAtlasSourceKind.Unit_;
  end
  else if AToken = 'program' then
  begin
    Sections.Kind := TAtlasSourceKind.Program_;
  end
  else if AToken = 'library' then
  begin
    Sections.Kind := TAtlasSourceKind.Library_;
  end
  else if AToken = 'package' then
  begin
    Sections.Kind := TAtlasSourceKind.Package;
  end
  else
  begin
    Result := False;
  end;
  Previous := AToken;
end;

procedure TSectionScan.UnitUses;
begin
  // uses gehört zum Abschnitt, in dem es steht; je Abschnitt zählt die erste Klausel.
  if Sections.ImplementationPart.Found then
  begin
    if not Sections.ImplementationUses.Start.Found then
    begin
      OpenUses := @Sections.ImplementationUses;
    end;
  end
  else if Sections.InterfacePart.Found and not Sections.InterfaceUses.Start.Found then
  begin
    OpenUses := @Sections.InterfaceUses;
  end;
end;

procedure TSectionScan.FrontPart(const AToken: TSectionToken);
var
  mInImplementation: Boolean;
begin
  mInImplementation := Sections.ImplementationPart.Found;
  if (AToken.Text = 'interface') and not Sections.InterfacePart.Found and not mInImplementation and
    (AfterHeader or (Previous <> '=')) then
  begin
    Sections.InterfacePart := AToken.Mark;
  end
  else if (AToken.Text = 'implementation') and not mInImplementation then
  begin
    Sections.ImplementationPart := AToken.Mark;
  end;
end;

procedure TSectionScan.BackPart(const AToken: TSectionToken);
begin
  if not Sections.ImplementationPart.Found then
  begin
    Exit;
  end;
  if (AToken.Text = 'initialization') and not Sections.Initialization_.Found then
  begin
    Sections.Initialization_ := AToken.Mark;
  end
  else if (AToken.Text = 'finalization') and not Sections.Finalization_.Found then
  begin
    Sections.Finalization_ := AToken.Mark;
  end;
end;
procedure TSectionScan.UnitToken(const AToken: TSectionToken);
begin
  if AToken.Text = 'uses' then
  begin
    UnitUses;
    if OpenUses <> nil then
    begin
      OpenUses^.Start := AToken.Mark;
    end;
  end
  else
  begin
    FrontPart(AToken);
    BackPart(AToken);
  end;
end;

procedure TSectionScan.HeaderToken(const AToken: TSectionToken);
var
  mKeyword: string;
begin
  mKeyword := 'uses';
  if Sections.Kind = TAtlasSourceKind.Package then
  begin
    mKeyword := 'contains';
  end;
  if HeaderDone and not Sections.HeaderUses.Start.Found and (AToken.Text = mKeyword) then
  begin
    OpenUses := @Sections.HeaderUses;
    OpenUses^.Start := AToken.Mark;
  end;
end;

function TSectionScan.Take(const AToken: TSectionToken): Boolean;
begin
  Result := True;
  if OpenUses <> nil then
  begin
    if AToken.Text = ';' then
    begin
      OpenUses^.Stop := AToken.Mark;
      OpenUses := nil;
    end;
  end
  else if not HeaderDone and (AToken.Text = ';') then
  begin
    HeaderDone := True;
    AfterHeader := True;
  end
  else
  begin
    if Sections.Kind = TAtlasSourceKind.Unit_ then
    begin
      UnitToken(AToken);
    end
    else
    begin
      HeaderToken(AToken);
    end;
    // „end.“ beendet die Unit; danach steht nichts mehr, was zählt.
    Result := not ((Previous = 'end') and (AToken.Text = '.'));
    AfterHeader := False;
  end;
  Previous := AToken.Text;
end;

class function TAtlasSectionScanner.Scan(const AText: string): TAtlasUnitSections;
begin
  Result := Scan(TTextLines.SplitLines(AText));
end;

class function TAtlasSectionScanner.Scan(const ALines: TArray<string>): TAtlasUnitSections;
var
  mReader: TTokenReader;
  mScan: TSectionScan;
  mToken: TSectionToken;
begin
  mScan := Default(TSectionScan);
  mScan.Sections.Kind := TAtlasSourceKind.Include;
  mReader := Default(TTokenReader);
  mReader.Lines := ALines;
  mReader.Position := 1;
  // Ohne Kopf (.inc): keine Abschnitte.
  if mReader.Next(mToken) and mScan.TakeKind(mToken.Text) then
  begin
    while mReader.Next(mToken) do
    begin
      if not mScan.Take(mToken) then
      begin
        Break;
      end;
    end;
  end;
  Result := mScan.Sections;
end;

end.
