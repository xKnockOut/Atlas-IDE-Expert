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
  Atlas.Text.Chars;

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
{$SCOPEDENUMS ON}
  /// <summary>Was Scan von einem Token wissen muss: eines der Wörter, auf die es achtet, ein Zeichen oder
  /// irgendein anderes Wort. Ohne String je Token (große Units haben Hunderttausende Wörter).</summary>
  TSectionWord = (Other, Semicolon, Equals, Dot, Ampersand, Unit_, Program_, Library_, Package, Uses_,
    Contains, Interface_, Implementation_, Initialization_, Finalization_, End_);
{$SCOPEDENUMS OFF}

  /// <summary>Token und seine Stelle, 0-basiert.</summary>
  TSectionToken = record
    Word: TSectionWord;
    Line: Integer;
    Character: Integer;
    function Mark: TAtlasSectionMark;
  end;

  /// <summary>Liest Wörter und die Zeichen „;“, „=“ und „.“ außerhalb von Kommentaren und Strings; direkt im
  /// ganzen Text, ohne ihn in Zeilen zu zerlegen.</summary>
  TTokenReader = record
    Text: string;
    /// <summary>Nächstes Zeichen, 1-basiert.</summary>
    Position: Integer;
    Line: Integer;
    /// <summary>Position des ersten Zeichens der Zeile Line.</summary>
    LineStart: Integer;
    /// <summary>Offener Kommentar über Zeilen: '{' oder '(' für (* *); #0 = keiner.</summary>
    Comment: Char;
    /// <summary>Anzahl der Anführungszeichen eines offenen mehrzeiligen Strings; 0 = keiner.</summary>
    MultiQuotes: Integer;
    /// <summary>Nächstes Token; False am Ende des Textes.</summary>
    function Next(out AToken: TSectionToken): Boolean;
  private
    function IsBreak(APosition: Integer): Boolean;
    /// <summary>Zeilenumbruch an Position überspringen; False, wenn dort keiner steht.</summary>
    function SkipBreak: Boolean;
    /// <summary>Bis vor den nächsten Zeilenumbruch.</summary>
    procedure SkipToLineEnd;
    /// <summary>Am Zeilenanfang im mehrzeiligen String: Ende suchen, sonst die Zeile überspringen.</summary>
    procedure SkipMultiLine;
    /// <summary>Ein Zeichen im offenen Kommentar weiter.</summary>
    procedure SkipInComment;
    /// <summary>Kommentar, der bei Position beginnt, öffnen bzw. überspringen; sonst ein Zeichen weiter.</summary>
    procedure OpenComment;
    /// <summary>Steht ab APosition bis zum Zeilenende nur Leerraum?</summary>
    function BlankToLineEnd(APosition: Integer): Boolean;
    /// <summary>String ab Position überspringen; ''' am Zeilenende öffnet einen mehrzeiligen.</summary>
    procedure SkipString;
    /// <summary>Bezeichner ab Position überspringen.</summary>
    procedure SkipIdent;
    /// <summary>Token ab Position oder ein Zeichen weiter; False ohne Token.</summary>
    function TokenAt(var AToken: TSectionToken): Boolean;
    function Emit(AWord: TSectionWord; AStart: Integer; var AToken: TSectionToken): Boolean;
  end;

  /// <summary>Zustand von Scan: Kopf gelesen, offene uses-Klausel, vorheriges Token.</summary>
  TSectionScan = record
    Sections: TAtlasUnitSections;
    HeaderDone: Boolean;
    AfterHeader: Boolean;
    OpenUses: ^TAtlasUsesMark;
    Previous: TSectionWord;
    /// <summary>Art aus dem ersten Wort; False ohne Kopf (.inc).</summary>
    function TakeKind(AWord: TSectionWord): Boolean;
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

const
  /// <summary>Die Wörter, auf die Scan achtet, klein.</summary>
  cSectionWords: array[TSectionWord.Unit_..TSectionWord.End_] of string = ('unit', 'program', 'library',
    'package', 'uses', 'contains', 'interface', 'implementation', 'initialization', 'finalization', 'end');

function TSectionToken.Mark: TAtlasSectionMark;
begin
  Result := TAtlasSectionMark.At(Line, Character);
end;

/// <summary>True, wenn ab AStart das Wort AWord (klein) steht, Groß-/Kleinschreibung egal.</summary>
function WordAt(const AText: string; AStart: Integer; const AWord: string): Boolean;
var
  mIndex: Integer;
  mChar: Char;
begin
  for mIndex := 1 to Length(AWord) do
  begin
    mChar := AText[AStart + mIndex - 1];
    if CharInSet(mChar, ['A'..'Z']) then
    begin
      mChar := Char(Ord(mChar) + 32);
    end;
    if mChar <> AWord[mIndex] then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

/// <summary>Wort ab AStart mit ALength Zeichen.</summary>
function SectionWordAt(const AText: string; AStart, ALength: Integer): TSectionWord;
var
  mWord: TSectionWord;
begin
  for mWord := Low(cSectionWords) to High(cSectionWords) do
  begin
    if (Length(cSectionWords[mWord]) = ALength) and WordAt(AText, AStart, cSectionWords[mWord]) then
    begin
      Exit(mWord);
    end;
  end;
  Result := TSectionWord.Other;
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

function TTokenReader.IsBreak(APosition: Integer): Boolean;
begin
  Result := CharInSet(Text[APosition], [#10, #13]);
end;

function TTokenReader.SkipBreak: Boolean;
begin
  Result := IsBreak(Position);
  if not Result then
  begin
    Exit;
  end;
  if (Text[Position] = #13) and (Position < Length(Text)) and (Text[Position + 1] = #10) then
  begin
    Inc(Position);
  end;
  Inc(Position);
  Inc(Line);
  LineStart := Position;
end;

procedure TTokenReader.SkipToLineEnd;
begin
  while (Position <= Length(Text)) and not IsBreak(Position) do
  begin
    Inc(Position);
  end;
end;

procedure TTokenReader.SkipMultiLine;
var
  mStart: Integer;
begin
  // Mehrzeiliger String: endet an einer Zeile, die (nach Einrückung) mit gleich vielen ''' beginnt.
  mStart := Position;
  while (mStart <= Length(Text)) and CharInSet(Text[mStart], [' ', #9]) do
  begin
    Inc(mStart);
  end;
  if QuoteRun(Text, mStart) >= MultiQuotes then
  begin
    Position := mStart + MultiQuotes;
    MultiQuotes := 0;
  end
  else
  begin
    SkipToLineEnd;
  end;
end;

procedure TTokenReader.SkipInComment;
begin
  if (Comment = '{') and (Text[Position] = '}') then
  begin
    Comment := #0;
  end
  else if (Comment = '(') and (Text[Position] = '*') and (Position < Length(Text)) and
    (Text[Position + 1] = ')') then
  begin
    Comment := #0;
    Inc(Position);
  end;
  Inc(Position);
end;

procedure TTokenReader.OpenComment;
var
  mNext: Char;
begin
  mNext := #0;
  if Position < Length(Text) then
  begin
    mNext := Text[Position + 1];
  end;
  if Text[Position] = '{' then
  begin
    Comment := '{';
    Inc(Position);
  end
  else if (Text[Position] = '(') and (mNext = '*') then
  begin
    Comment := '(';
    Inc(Position, 2);
  end
  else if (Text[Position] = '/') and (mNext = '/') then
  begin
    SkipToLineEnd;
  end
  else
  begin
    Inc(Position);
  end;
end;

function TTokenReader.BlankToLineEnd(APosition: Integer): Boolean;
var
  mIndex: Integer;
begin
  mIndex := APosition;
  while (mIndex <= Length(Text)) and not IsBreak(mIndex) do
  begin
    if Text[mIndex] > ' ' then
    begin
      Exit(False);
    end;
    Inc(mIndex);
  end;
  Result := True;
end;

procedure TTokenReader.SkipString;
var
  mRun: Integer;
begin
  mRun := QuoteRun(Text, Position);
  // ''' (oder mehr, ungerade) am Zeilenende öffnet einen mehrzeiligen String (Delphi 12).
  if (mRun >= 3) and Odd(mRun) and BlankToLineEnd(Position + mRun) then
  begin
    MultiQuotes := mRun;
    SkipToLineEnd;
    Exit;
  end;
  // Gewöhnlicher String: '' ist ein Anführungszeichen darin; er endet spätestens am Zeilenende.
  Inc(Position);
  while (Position <= Length(Text)) and not IsBreak(Position) do
  begin
    if Text[Position] <> '''' then
    begin
      Inc(Position);
    end
    else if (Position < Length(Text)) and (Text[Position + 1] = '''') then
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

procedure TTokenReader.SkipIdent;
begin
  while (Position <= Length(Text)) and TTextChars.IsIdentChar(Text[Position]) do
  begin
    Inc(Position);
  end;
end;

function TTokenReader.Emit(AWord: TSectionWord; AStart: Integer; var AToken: TSectionToken): Boolean;
begin
  AToken.Word := AWord;
  AToken.Line := Line;
  AToken.Character := AStart - LineStart;
  Result := True;
end;

function TTokenReader.TokenAt(var AToken: TSectionToken): Boolean;
var
  mStart: Integer;
begin
  Result := False;
  mStart := Position;
  case Text[Position] of
    '{', '(', '/':
      OpenComment;
    '''':
      SkipString;
    ';':
      begin
        Inc(Position);
        Result := Emit(TSectionWord.Semicolon, mStart, AToken);
      end;
    '=':
      begin
        Inc(Position);
        Result := Emit(TSectionWord.Equals, mStart, AToken);
      end;
    '.':
      begin
        Inc(Position);
        Result := Emit(TSectionWord.Dot, mStart, AToken);
      end;
    '&':
      begin
        // &interface ist ein Bezeichner, kein Schlüsselwort.
        Inc(Position);
        Result := (Position <= Length(Text)) and TTextChars.IsIdentStart(Text[Position]);
        SkipIdent;
        if Result then
        begin
          Emit(TSectionWord.Ampersand, Position, AToken);
        end;
      end;
  else
    if not TTextChars.IsIdentStart(Text[Position]) then
    begin
      Inc(Position);
      Exit;
    end;
    SkipIdent;
    Result := Emit(SectionWordAt(Text, mStart, Position - mStart), mStart, AToken);
  end;
end;

function TTokenReader.Next(out AToken: TSectionToken): Boolean;
begin
  AToken := Default(TSectionToken);
  while Position <= Length(Text) do
  begin
    if SkipBreak then
    begin
      // Zeilenanfang: ein offener mehrzeiliger String endet nur hier.
      if MultiQuotes > 0 then
      begin
        SkipMultiLine;
      end;
    end
    else if MultiQuotes > 0 then
    begin
      SkipToLineEnd;
    end
    else if Comment <> #0 then
    begin
      SkipInComment;
    end
    else if TokenAt(AToken) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TSectionScan.TakeKind(AWord: TSectionWord): Boolean;
begin
  Result := True;
  case AWord of
    TSectionWord.Unit_:
      Sections.Kind := TAtlasSourceKind.Unit_;
    TSectionWord.Program_:
      Sections.Kind := TAtlasSourceKind.Program_;
    TSectionWord.Library_:
      Sections.Kind := TAtlasSourceKind.Library_;
    TSectionWord.Package:
      Sections.Kind := TAtlasSourceKind.Package;
  else
    Result := False;
  end;
  Previous := AWord;
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
  if (AToken.Word = TSectionWord.Interface_) and not Sections.InterfacePart.Found and not mInImplementation and
    (AfterHeader or (Previous <> TSectionWord.Equals)) then
  begin
    Sections.InterfacePart := AToken.Mark;
  end
  else if (AToken.Word = TSectionWord.Implementation_) and not mInImplementation then
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
  if (AToken.Word = TSectionWord.Initialization_) and not Sections.Initialization_.Found then
  begin
    Sections.Initialization_ := AToken.Mark;
  end
  else if (AToken.Word = TSectionWord.Finalization_) and not Sections.Finalization_.Found then
  begin
    Sections.Finalization_ := AToken.Mark;
  end;
end;

procedure TSectionScan.UnitToken(const AToken: TSectionToken);
begin
  if AToken.Word = TSectionWord.Uses_ then
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
  mKeyword: TSectionWord;
begin
  mKeyword := TSectionWord.Uses_;
  if Sections.Kind = TAtlasSourceKind.Package then
  begin
    mKeyword := TSectionWord.Contains;
  end;
  if HeaderDone and not Sections.HeaderUses.Start.Found and (AToken.Word = mKeyword) then
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
    if AToken.Word = TSectionWord.Semicolon then
    begin
      OpenUses^.Stop := AToken.Mark;
      OpenUses := nil;
    end;
  end
  else if not HeaderDone and (AToken.Word = TSectionWord.Semicolon) then
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
    Result := not ((Previous = TSectionWord.End_) and (AToken.Word = TSectionWord.Dot));
    AfterHeader := False;
  end;
  Previous := AToken.Word;
end;

class function TAtlasSectionScanner.Scan(const ALines: TArray<string>): TAtlasUnitSections;
begin
  Result := Scan(string.Join(#10, ALines));
end;

class function TAtlasSectionScanner.Scan(const AText: string): TAtlasUnitSections;
var
  mReader: TTokenReader;
  mScan: TSectionScan;
  mToken: TSectionToken;
begin
  mScan := Default(TSectionScan);
  mScan.Sections.Kind := TAtlasSourceKind.Include;
  mReader := Default(TTokenReader);
  mReader.Text := AText;
  mReader.Position := 1;
  mReader.LineStart := 1;
  // Ohne Kopf (.inc): keine Abschnitte.
  if mReader.Next(mToken) and mScan.TakeKind(mToken.Word) then
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
