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
    class function Scan(const ALines: TArray<string>): TAtlasUnitSections; static;
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
    Exit(TAtlasCodeSection.UsesClause);
  end;
  if Finalization_.Before(ALine, ACharacter) then
  begin
    Exit(TAtlasCodeSection.Finalization_);
  end;
  if Initialization_.Before(ALine, ACharacter) then
  begin
    Exit(TAtlasCodeSection.Initialization_);
  end;
  if ImplementationPart.Before(ALine, ACharacter) then
  begin
    Exit(TAtlasCodeSection.ImplementationPart);
  end;
  if InterfacePart.Before(ALine, ACharacter) then
  begin
    Exit(TAtlasCodeSection.InterfacePart);
  end;
  Result := TAtlasCodeSection.None;
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
    function Next(out AToken: string; out ALine, ACharacter: Integer): Boolean;
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

function TTokenReader.Next(out AToken: string; out ALine, ACharacter: Integer): Boolean;
var
  Text: string;
  Start, Run: Integer;
  Escaped: Boolean;
begin
  AToken := '';
  ALine := 0;
  ACharacter := 0;
  while Line <= High(Lines) do
  begin
    Text := Lines[Line];
    if MultiQuotes > 0 then
    begin
      // Mehrzeiliger String: endet an einer Zeile, die (nach Einrückung) mit gleich vielen ''' beginnt.
      Start := 1;
      while (Start <= Length(Text)) and CharInSet(Text[Start], [' ', #9]) do
      begin
        Inc(Start);
      end;
      if QuoteRun(Text, Start) >= MultiQuotes then
      begin
        Position := Start + MultiQuotes;
        MultiQuotes := 0;
      end
      else
      begin
        Inc(Line);
        Position := 1;
        Continue;
      end;
    end;
    while Position <= Length(Text) do
    begin
      if Comment = '{' then
      begin
        if Text[Position] = '}' then
        begin
          Comment := #0;
        end;
        Inc(Position);
        Continue;
      end;
      if Comment = '(' then
      begin
        if (Text[Position] = '*') and (Position < Length(Text)) and (Text[Position + 1] = ')') then
        begin
          Comment := #0;
          Inc(Position);
        end;
        Inc(Position);
        Continue;
      end;
      case Text[Position] of
        '{':
          begin
            Comment := '{';
            Inc(Position);
          end;
        '(':
          if (Position < Length(Text)) and (Text[Position + 1] = '*') then
          begin
            Comment := '(';
            Inc(Position, 2);
          end
          else
          begin
            Inc(Position);
          end;
        '/':
          if (Position < Length(Text)) and (Text[Position + 1] = '/') then
          begin
            Position := Length(Text) + 1;
          end
          else
          begin
            Inc(Position);
          end;
        '''':
          begin
            Run := QuoteRun(Text, Position);
            // ''' (oder mehr, ungerade) am Zeilenende öffnet einen mehrzeiligen String (Delphi 12).
            if (Run >= 3) and Odd(Run) and (Trim(Copy(Text, Position + Run, MaxInt)) = '') then
            begin
              MultiQuotes := Run;
              Position := Length(Text) + 1;
              Continue;
            end;
            // Gewöhnlicher String: '' ist ein Anführungszeichen darin.
            Inc(Position);
            while Position <= Length(Text) do
            begin
              if Text[Position] = '''' then
              begin
                if (Position < Length(Text)) and (Text[Position + 1] = '''') then
                begin
                  Inc(Position, 2);
                end
                else
                begin
                  Inc(Position);
                  Break;
                end;
              end
              else
              begin
                Inc(Position);
              end;
            end;
          end;
        ';', '=', '.':
          begin
            AToken := Text[Position];
            ALine := Line;
            ACharacter := Position - 1;
            Inc(Position);
            Exit(True);
          end;
        '&':
          begin
            // &interface ist ein Bezeichner, kein Schlüsselwort.
            Inc(Position);
            Escaped := (Position <= Length(Text)) and TTextChars.IsIdentStart(Text[Position]);
            while (Position <= Length(Text)) and TTextChars.IsIdentChar(Text[Position]) do
            begin
              Inc(Position);
            end;
            if Escaped then
            begin
              AToken := '&';
              ALine := Line;
              ACharacter := Position - 1;
              Exit(True);
            end;
          end;
      else
        if TTextChars.IsIdentStart(Text[Position]) then
        begin
          Start := Position;
          while (Position <= Length(Text)) and TTextChars.IsIdentChar(Text[Position]) do
          begin
            Inc(Position);
          end;
          AToken := LowerCase(Copy(Text, Start, Position - Start));
          ALine := Line;
          ACharacter := Start - 1;
          Exit(True);
        end
        else
        begin
          Inc(Position);
        end;
      end;
    end;
    Inc(Line);
    Position := 1;
  end;
  Result := False;
end;

class function TAtlasSectionScanner.Scan(const ALines: TArray<string>): TAtlasUnitSections;
var
  Reader: TTokenReader;
  Token, Previous: string;
  Line, Character: Integer;
  First, HeaderDone, AfterHeader: Boolean;
  OpenUses: ^TAtlasUsesMark;
begin
  Result := Default(TAtlasUnitSections);
  Result.Kind := TAtlasSourceKind.Include;
  Reader := Default(TTokenReader);
  Reader.Lines := ALines;
  Reader.Position := 1;
  First := True;
  HeaderDone := False;
  AfterHeader := False;
  OpenUses := nil;
  Previous := '';
  while Reader.Next(Token, Line, Character) do
  begin
    if First then
    begin
      First := False;
      if Token = 'unit' then
      begin
        Result.Kind := TAtlasSourceKind.Unit_;
      end
      else if Token = 'program' then
      begin
        Result.Kind := TAtlasSourceKind.Program_;
      end
      else if Token = 'library' then
      begin
        Result.Kind := TAtlasSourceKind.Library_;
      end
      else if Token = 'package' then
      begin
        Result.Kind := TAtlasSourceKind.Package;
      end
      else
      begin
        // Ohne Kopf (.inc): keine Abschnitte.
        Exit;
      end;
      Previous := Token;
      Continue;
    end;
    if OpenUses <> nil then
    begin
      if Token = ';' then
      begin
        OpenUses^.Stop := TAtlasSectionMark.At(Line, Character);
        OpenUses := nil;
      end;
      Previous := Token;
      Continue;
    end;
    if not HeaderDone then
    begin
      if Token = ';' then
      begin
        HeaderDone := True;
        AfterHeader := True;
        Previous := Token;
        Continue;
      end;
    end;
    if Result.Kind = TAtlasSourceKind.Unit_ then
    begin
      if (Token = 'interface') and not Result.InterfacePart.Found and not Result.ImplementationPart.Found and
        (AfterHeader or (Previous <> '=')) then
      begin
        Result.InterfacePart := TAtlasSectionMark.At(Line, Character);
      end
      else if (Token = 'implementation') and not Result.ImplementationPart.Found then
      begin
        Result.ImplementationPart := TAtlasSectionMark.At(Line, Character);
      end
      else if (Token = 'initialization') and Result.ImplementationPart.Found and not Result.Initialization_.Found then
      begin
        Result.Initialization_ := TAtlasSectionMark.At(Line, Character);
      end
      else if (Token = 'finalization') and Result.ImplementationPart.Found and not Result.Finalization_.Found then
      begin
        Result.Finalization_ := TAtlasSectionMark.At(Line, Character);
      end
      else if Token = 'uses' then
      begin
        if Result.ImplementationPart.Found then
        begin
          if not Result.ImplementationUses.Start.Found then
          begin
            OpenUses := @Result.ImplementationUses;
          end;
        end
        else if Result.InterfacePart.Found and not Result.InterfaceUses.Start.Found then
        begin
          OpenUses := @Result.InterfaceUses;
        end;
        if OpenUses <> nil then
        begin
          OpenUses^.Start := TAtlasSectionMark.At(Line, Character);
        end;
      end;
    end
    else if HeaderDone and not Result.HeaderUses.Start.Found and
      (((Result.Kind <> TAtlasSourceKind.Package) and (Token = 'uses')) or
      ((Result.Kind = TAtlasSourceKind.Package) and (Token = 'contains'))) then
    begin
      OpenUses := @Result.HeaderUses;
      OpenUses^.Start := TAtlasSectionMark.At(Line, Character);
    end;
    // „end.“ beendet die Unit; danach steht nichts mehr, was zählt.
    if (Previous = 'end') and (Token = '.') then
    begin
      Break;
    end;
    AfterHeader := False;
    Previous := Token;
  end;
end;

end.
