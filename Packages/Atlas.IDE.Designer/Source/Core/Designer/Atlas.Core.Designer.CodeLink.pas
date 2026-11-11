unit Atlas.Core.Designer.CodeLink;

// Vom Code zur Komponente im Designer (#511), ohne VCL und Windows:
// - ChainAt: Bezeichnerkette unter dem Cursor bis einschließlich des Teils,
//   auf dem er steht („Self.btnOk.Caption“ mit dem Cursor auf btnOk ergibt
//   Self, btnOk).
// - MethodAt: Methode, in deren Kopf oder Rumpf eine Zeile liegt (Name ohne
//   Klasse), für „Cursor in einem Handler“.
// - Targets: Komponenten des Formulars zur Stelle. Zuerst ein Teil der Kette,
//   der eine Komponente benennt (Feld oder Feldnutzung); sonst alle
//   Komponenten, deren Ereignis den Bezeichner unter dem Cursor oder die
//   umschließende Methode als Handler hat, je Ereignis ein Ziel.

interface

uses
  Atlas.Core.Designer.Components;

type
  /// <summary>Komponente im Designer; Event = Ereignis bei einem Handler („OnClick“), sonst ''.</summary>
  TAtlasDesignerTarget = record
    Component: string;
    Event: string;
    class function Create(const AComponent, AEvent: string): TAtlasDesignerTarget; static;
    /// <summary>„btnOk“ bzw. „btnOk.OnClick“.</summary>
    function Text: string;
  end;

  TAtlasDesignerLink = class
  public
    /// <summary>Teile der Bezeichnerkette um ACharacter (0-basiert) bis einschließlich des Teils unter dem Cursor;
    /// leer ohne Bezeichner.</summary>
    class function ChainAt(const ALine: string; ACharacter: Integer): TArray<string>; static;
    /// <summary>Methode (ohne Klasse), in deren Kopf oder Rumpf die Zeile ALine (0-basiert) liegt; '' sonst.</summary>
    class function MethodAt(const ALines: TArray<string>; ALine: Integer): string; static;
    /// <summary>Ziele im Formular zu AChain und AMethod; AItems sind die Komponenten samt Formular.</summary>
    class function Targets(const AItems: TArray<TAtlasDesignerItem>; const AChain: TArray<string>;
      const AMethod: string): TArray<TAtlasDesignerTarget>; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Text.Chars;

{ TAtlasDesignerTarget }

class function TAtlasDesignerTarget.Create(const AComponent, AEvent: string): TAtlasDesignerTarget;
begin
  Result.Component := AComponent;
  Result.Event := AEvent;
end;

function TAtlasDesignerTarget.Text: string;
begin
  Result := Component;
  if Event <> '' then
  begin
    Result := Result + '.' + Event;
  end;
end;

{ TAtlasDesignerLink }

/// <summary>Leerraum vor bzw. nach APos (1-basiert) überspringen.</summary>
function SkipBlanks(const ALine: string; APos, AStep: Integer): Integer;
begin
  Result := APos;
  while (Result >= 1) and (Result <= Length(ALine)) and (ALine[Result] = ' ') do
  begin
    Inc(Result, AStep);
  end;
end;

/// <summary>Position (1-basiert) des Bezeichnerzeichens unter ACharacter (0-basiert); der Cursor darf direkt
/// hinter dem Bezeichner stehen. 0 ohne Bezeichner.</summary>
function IdentAt(const ALine: string; ACharacter: Integer): Integer;
begin
  Result := ACharacter + 1;
  if ((Result > Length(ALine)) or not TTextChars.IsIdentChar(ALine[Result])) and (Result > 1) and
    TTextChars.IsIdentChar(ALine[Result - 1]) then
  begin
    Dec(Result);
  end;
  if (Result < 1) or (Result > Length(ALine)) or not TTextChars.IsIdentChar(ALine[Result]) then
  begin
    Result := 0;
  end;
end;

class function TAtlasDesignerLink.ChainAt(const ALine: string; ACharacter: Integer): TArray<string>;
var
  mStart, mStop, mPos: Integer;
begin
  Result := nil;
  mPos := IdentAt(ALine, ACharacter);
  if mPos = 0 then
  begin
    Exit;
  end;
  mStop := mPos;
  while (mStop < Length(ALine)) and TTextChars.IsIdentChar(ALine[mStop + 1]) do
  begin
    Inc(mStop);
  end;
  // Rückwärts über „Teil.“ bis zum Anfang der Kette.
  mStart := mPos;
  repeat
    while (mStart > 1) and TTextChars.IsIdentChar(ALine[mStart - 1]) do
    begin
      Dec(mStart);
    end;
    Result := [Copy(ALine, mStart, mStop - mStart + 1)] + Result;
    mPos := SkipBlanks(ALine, mStart - 1, -1);
    if (mPos < 1) or (ALine[mPos] <> '.') then
    begin
      Break;
    end;
    mStop := SkipBlanks(ALine, mPos - 1, -1);
    if (mStop < 1) or not TTextChars.IsIdentChar(ALine[mStop]) then
    begin
      Break;
    end;
    mStart := mStop;
  until False;
end;

/// <summary>Kopf einer Routine in der Zeile? AName: Name einer Methode („procedure TKlasse.Name“), '' bei einer
/// Routine ohne Klasse.</summary>
function MethodHead(const ALine: string; out AName: string): Boolean;
var
  mText, mWord: string;
  mPos, mDot: Integer;
begin
  Result := False;
  AName := '';
  mText := Trim(ALine);
  mPos := Pos(' ', mText);
  if mPos = 0 then
  begin
    Exit;
  end;
  mWord := LowerCase(Copy(mText, 1, mPos - 1));
  if mWord = 'class' then
  begin
    mText := Trim(Copy(mText, mPos + 1, MaxInt));
    mPos := Pos(' ', mText);
    if mPos = 0 then
    begin
      Exit;
    end;
    mWord := LowerCase(Copy(mText, 1, mPos - 1));
  end;
  if (mWord <> 'procedure') and (mWord <> 'function') and (mWord <> 'constructor') and (mWord <> 'destructor') then
  begin
    Exit;
  end;
  Result := True;
  mText := Trim(Copy(mText, mPos + 1, MaxInt));
  mPos := 1;
  while (mPos <= Length(mText)) and (TTextChars.IsIdentChar(mText[mPos]) or (mText[mPos] = '.')) do
  begin
    Inc(mPos);
  end;
  mText := Copy(mText, 1, mPos - 1);
  mDot := LastDelimiter('.', mText);
  // Nur Methoden einer Klasse (mit Punkt): Handler sind Methoden des Formulars.
  if mDot > 0 then
  begin
    AName := Copy(mText, mDot + 1, MaxInt);
  end;
end;

/// <summary>Beginnt die Zeile mit „implementation“, „initialization“, „finalization“ oder „end.“?</summary>
function IsSectionEnd(const ALine: string): Boolean;
var
  mText: string;
begin
  mText := LowerCase(Trim(ALine));
  Result := mText.StartsWith('implementation') or mText.StartsWith('initialization') or
    mText.StartsWith('finalization') or (mText = 'end.');
end;

class function TAtlasDesignerLink.MethodAt(const ALines: TArray<string>; ALine: Integer): string;
var
  mIndex: Integer;
begin
  Result := '';
  if (ALine < 0) or (ALine > High(ALines)) then
  begin
    Exit;
  end;
  // Rückwärts zum nächsten Methodenkopf; ein Abschnittswechsel dazwischen heißt: außerhalb jeder Methode.
  for mIndex := ALine downto 0 do
  begin
    // Der nächste Routinenkopf entscheidet, auch eine Routine ohne Klasse.
    if MethodHead(ALines[mIndex], Result) then
    begin
      Exit;
    end;
    if (mIndex < ALine) and IsSectionEnd(ALines[mIndex]) then
    begin
      Exit;
    end;
  end;
end;

/// <summary>Ereignisse von AItem mit dem Handler AHandler („OnClick = btnOkClick“).</summary>
function EventsWith(const AItem: TAtlasDesignerItem; const AHandler: string): TArray<string>;
var
  mEvent: string;
  mPos: Integer;
begin
  Result := nil;
  for mEvent in AItem.Events do
  begin
    mPos := Pos(' = ', mEvent);
    if (mPos > 0) and SameText(Trim(Copy(mEvent, mPos + 3, MaxInt)), AHandler) then
    begin
      Result := Result + [Trim(Copy(mEvent, 1, mPos - 1))];
    end;
  end;
end;

function HandlerTargets(const AItems: TArray<TAtlasDesignerItem>; const AHandler: string):
  TArray<TAtlasDesignerTarget>;
var
  mItem: TAtlasDesignerItem;
  mEvent: string;
begin
  Result := nil;
  if AHandler = '' then
  begin
    Exit;
  end;
  for mItem in AItems do
  begin
    for mEvent in EventsWith(mItem, AHandler) do
    begin
      Result := Result + [TAtlasDesignerTarget.Create(mItem.Name, mEvent)];
    end;
  end;
end;

class function TAtlasDesignerLink.Targets(const AItems: TArray<TAtlasDesignerItem>; const AChain: TArray<string>;
  const AMethod: string): TArray<TAtlasDesignerTarget>;
var
  mPart: string;
  mItem: TAtlasDesignerItem;
begin
  // Feld oder Feldnutzung: der erste Teil der Kette, der eine Komponente benennt (Self.btnOk, frmMain.btnOk).
  for mPart in AChain do
  begin
    for mItem in AItems do
    begin
      if SameText(mItem.Name, mPart) then
      begin
        Result := [TAtlasDesignerTarget.Create(mItem.Name, '')];
        Exit;
      end;
    end;
  end;
  // Handler: der Bezeichner unter dem Cursor, sonst die umschließende Methode.
  Result := nil;
  if Length(AChain) > 0 then
  begin
    Result := HandlerTargets(AItems, AChain[High(AChain)]);
  end;
  if Length(Result) = 0 then
  begin
    Result := HandlerTargets(AItems, AMethod);
  end;
end;

end.
