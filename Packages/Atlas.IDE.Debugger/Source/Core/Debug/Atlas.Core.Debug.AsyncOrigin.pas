unit Atlas.Core.Debug.AsyncOrigin;

// Herkunft eingereihter Methoden (#859, experimentell), ohne VCL und Open Tools API:
//   - TAtlasAsyncSites.Find: Aufrufstellen von TThread.Queue, TThread.Synchronize, TThread.ForceQueue, TTask.Run,
//     TTask.Create und TParallel.For im Quelltext einer Unit, je mit der Zeile des Aufrufs und der Zeile der
//     schließenden Klammer (dazwischen steht die übergebene anonyme Methode). Kommentare und Zeichenketten zählen
//     nicht. Aufrufe ohne „TThread.“ (Synchronize in einer Methode eines Threads) erfasst Atlas nicht, weil der Name
//     auch eine eigene Methode sein kann.
//   - TAtlasAsyncOrigins: je Aufrufstelle die letzten MaxPerSite Einreihungen (Thread, Stapel, Adresse der
//     übergebenen Methode, Reihenfolge); ältere fallen heraus. Take ordnet einen späteren Halt in der anonymen
//     Methode zu: mit bekannter Adresse die jüngste Einreihung mit dieser Adresse (Adressen werden wiederverwendet,
//     die jüngste gilt), sonst die älteste noch offene (Warteschlangen arbeiten der Reihe nach ab).

interface

uses
  Atlas.Core.Debug.CallStack;

type
  {$SCOPEDENUMS ON}
  TAtlasAsyncKind = (Queue, Synchronize, ForceQueue, TaskRun, TaskCreate, ParallelFor);
  {$SCOPEDENUMS OFF}

  TAtlasAsyncSite = record
    FileName: string;
    /// <summary>Zeile des Aufrufs, 1-basiert.</summary>
    Line: Integer;
    /// <summary>Zeile der schließenden Klammer, 1-basiert.</summary>
    EndLine: Integer;
    Kind: TAtlasAsyncKind;
    /// <summary>Liegt ALine (1-basiert) zwischen Aufruf und schließender Klammer?</summary>
    function Contains(ALine: Integer): Boolean;
  end;

  TAtlasAsyncSiteList = TArray<TAtlasAsyncSite>;

  TAtlasAsyncSites = record
  public
    /// <summary>Aufrufstellen in AText (Quelltext von AFileName).</summary>
    class function Find(const AFileName, AText: string): TAtlasAsyncSiteList; static;
    /// <summary>Innerste Aufrufstelle, die ALine (1-basiert) von AFileName enthält; -1 ohne.</summary>
    class function SiteAt(const ASites: TAtlasAsyncSiteList; const AFileName: string; ALine: Integer): Integer;
      static;
    /// <summary>„TThread.Queue“, „TTask.Run“, …</summary>
    class function KindName(AKind: TAtlasAsyncKind): string; static;
    /// <summary>Erste Aufrufstelle, deren Aufruf in Zeile ALine (1-basiert) von AFileName beginnt; -1 ohne.</summary>
    class function SiteOnLine(const ASites: TAtlasAsyncSiteList; const AFileName: string; ALine: Integer): Integer;
      static;
    /// <summary>Kopfzeile eines Rahmens in einer anonymen Methode („TForm1.Button1Click$0$Body“, „…$ActRec…“)?
    /// </summary>
    class function IsAnonymous(const AHeader: string): Boolean; static;
    /// <summary>Oberster Rahmen in AFrames, der in der anonymen Methode einer Aufrufstelle steht, ASite deren
    /// Index; -1 ohne.</summary>
    class function OriginFrame(const ASites: TAtlasAsyncSiteList; const AFrames: TAtlasDebugFrames;
      out ASite: Integer): Integer; static;
  end;

  TAtlasAsyncEntry = record
    Site: Integer;
    ThreadId: Cardinal;
    /// <summary>Adresse der übergebenen Methode; 0 = unbekannt.</summary>
    Address: UInt64;
    /// <summary>Stapel der Einreihung, oberster Rahmen zuerst.</summary>
    Frames: TAtlasDebugFrames;
    Sequence: Int64;
  end;

  TAtlasAsyncOrigins = record
  private
    FEntries: TArray<TAtlasAsyncEntry>;
    FSequence: Int64;
    function CountOf(ASite: Integer): Integer;
    function OldestOf(ASite: Integer): Integer;
  public
    /// <summary>Gemerkte Einreihungen je Aufrufstelle (debug.asyncOrigin.maxPerSite).</summary>
    MaxPerSite: Integer;
    /// <summary>Einreihung an ASite merken; die älteste der Stelle fällt heraus, wenn mehr als MaxPerSite.</summary>
    procedure Add(ASite: Integer; AThreadId: Cardinal; AAddress: UInt64; const AFrames: TAtlasDebugFrames);
    /// <summary>Einreihung zu einem Halt in der Methode von ASite (siehe Kopf); entfernt sie.</summary>
    function Take(ASite: Integer; AAddress: UInt64; out AEntry: TAtlasAsyncEntry): Boolean;
    function Count: Integer;
    procedure Clear;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  Atlas.Text.Chars;

type
  TCallName = record
    Owner: string;
    Method: string;
    Kind: TAtlasAsyncKind;
  end;

const
  cCalls: array[0..5] of TCallName = (
    (Owner: 'TThread'; Method: 'Queue'; Kind: TAtlasAsyncKind.Queue),
    (Owner: 'TThread'; Method: 'Synchronize'; Kind: TAtlasAsyncKind.Synchronize),
    (Owner: 'TThread'; Method: 'ForceQueue'; Kind: TAtlasAsyncKind.ForceQueue),
    (Owner: 'TTask'; Method: 'Run'; Kind: TAtlasAsyncKind.TaskRun),
    (Owner: 'TTask'; Method: 'Create'; Kind: TAtlasAsyncKind.TaskCreate),
    (Owner: 'TParallel'; Method: 'For'; Kind: TAtlasAsyncKind.ParallelFor));

/// <summary>Ende eines Kommentars ab AFrom: Index des letzten Zeichens von AClose; ohne Ende das Textende.</summary>
function CommentEnd(const AText, AClose: string; AFrom: Integer): Integer;
begin
  Result := Pos(AClose, AText, AFrom);
  if Result = 0 then
  begin
    Result := Length(AText);
  end
  else
  begin
    Result := Result + Length(AClose) - 1;
  end;
end;

/// <summary>Ende einer Zeichenkette ab dem Anführungszeichen bei AFrom ('' darin zählt mit); ohne Ende das Textende.
/// </summary>
function StringEnd(const AText: string; AFrom: Integer): Integer;
begin
  Result := AFrom + 1;
  while Result <= Length(AText) do
  begin
    if AText[Result] = '''' then
    begin
      if (Result = Length(AText)) or (AText[Result + 1] <> '''') then
      begin
        Exit;
      end;
      Inc(Result);
    end;
    Inc(Result);
  end;
  Result := Length(AText);
end;

/// <summary>Beginnt bei AIndex eine Zeichenkette oder ein Kommentar: Index des letzten Zeichens; sonst 0.</summary>
function SkippedEnd(const AText: string; AIndex: Integer): Integer;
var
  mNext: Char;
begin
  Result := 0;
  mNext := #0;
  if AIndex < Length(AText) then
  begin
    mNext := AText[AIndex + 1];
  end;
  case AText[AIndex] of
    '''':
      Result := StringEnd(AText, AIndex);
    '{':
      Result := CommentEnd(AText, '}', AIndex);
    '/':
      if mNext = '/' then
      begin
        Result := CommentEnd(AText, #10, AIndex) - 1;
      end;
    '(':
      if mNext = '*' then
      begin
        Result := CommentEnd(AText, '*)', AIndex + 2);
      end;
  end;
end;

/// <summary>AText mit Leerzeichen statt Kommentaren und Zeichenketten; Zeilenumbrüche bleiben.</summary>
function CodeOnly(const AText: string): string;
var
  mIndex, mEnd, mPos: Integer;
begin
  Result := AText;
  mIndex := 1;
  while mIndex <= Length(AText) do
  begin
    mEnd := SkippedEnd(AText, mIndex);
    for mPos := mIndex to mEnd do
    begin
      if not CharInSet(Result[mPos], [#10, #13]) then
      begin
        Result[mPos] := ' ';
      end;
    end;
    mIndex := Max(mIndex, mEnd) + 1;
  end;
end;

function IsSpace(AChar: Char): Boolean;
begin
  Result := CharInSet(AChar, [' ', #9, #10, #13]);
end;

/// <summary>Bezeichner ab AIndex (nach Leerraum); AIndex zeigt danach hinter ihn.</summary>
function ReadIdent(const AText: string; var AIndex: Integer): string;
var
  mStart: Integer;
begin
  while (AIndex <= Length(AText)) and IsSpace(AText[AIndex]) do
  begin
    Inc(AIndex);
  end;
  mStart := AIndex;
  while (AIndex <= Length(AText)) and TTextChars.IsIdentChar(AText[AIndex]) do
  begin
    Inc(AIndex);
  end;
  Result := Copy(AText, mStart, AIndex - mStart);
end;

/// <summary>Folgt ab AIndex (nach Leerraum) AChar? AIndex zeigt dann hinter ihn.</summary>
function Expect(const AText: string; var AIndex: Integer; AChar: Char): Boolean;
var
  mIndex: Integer;
begin
  mIndex := AIndex;
  while (mIndex <= Length(AText)) and IsSpace(AText[mIndex]) do
  begin
    Inc(mIndex);
  end;
  Result := (mIndex <= Length(AText)) and (AText[mIndex] = AChar);
  if Result then
  begin
    AIndex := mIndex + 1;
  end;
end;

/// <summary>Index der zu AOpen (Index hinter der öffnenden Klammer) passenden schließenden Klammer.</summary>
function ClosingParen(const AText: string; AOpen: Integer): Integer;
var
  mDepth: Integer;
begin
  mDepth := 1;
  Result := AOpen;
  while Result <= Length(AText) do
  begin
    if AText[Result] = '(' then
    begin
      Inc(mDepth);
    end
    else if AText[Result] = ')' then
    begin
      Dec(mDepth);
      if mDepth = 0 then
      begin
        Exit;
      end;
    end;
    Inc(Result);
  end;
  Result := Length(AText);
end;

function LineOf(const AText: string; AIndex: Integer): Integer;
var
  mPos: Integer;
begin
  Result := 1;
  for mPos := 1 to AIndex - 1 do
  begin
    if AText[mPos] = #10 then
    begin
      Inc(Result);
    end;
  end;
end;

{ TAtlasAsyncSite }

function TAtlasAsyncSite.Contains(ALine: Integer): Boolean;
begin
  Result := (ALine >= Line) and (ALine <= EndLine);
end;

{ TAtlasAsyncSites }

class function TAtlasAsyncSites.KindName(AKind: TAtlasAsyncKind): string;
var
  mCall: TCallName;
begin
  for mCall in cCalls do
  begin
    if mCall.Kind = AKind then
    begin
      Exit(mCall.Owner + '.' + mCall.Method);
    end;
  end;
  Result := '';
end;

class function TAtlasAsyncSites.Find(const AFileName, AText: string): TAtlasAsyncSiteList;
var
  mCode, mOwner, mMethod: string;
  mIndex, mNext, mStart: Integer;
  mCall: TCallName;
  mSite: TAtlasAsyncSite;
begin
  Result := nil;
  mCode := CodeOnly(AText);
  mIndex := 1;
  while mIndex <= Length(mCode) do
  begin
    // Nur am Anfang eines Bezeichners, nicht hinter einem Punkt (System.Classes.TThread zählt über „TThread.“).
    if (not TTextChars.IsIdentChar(mCode[mIndex])) or ((mIndex > 1) and TTextChars.IsIdentChar(mCode[mIndex - 1])) then
    begin
      Inc(mIndex);
      Continue;
    end;
    mStart := mIndex;
    mNext := mIndex;
    mOwner := ReadIdent(mCode, mNext);
    mIndex := mNext;
    if not Expect(mCode, mNext, '.') then
    begin
      Continue;
    end;
    mMethod := ReadIdent(mCode, mNext);
    for mCall in cCalls do
    begin
      if SameText(mOwner, mCall.Owner) and SameText(mMethod, mCall.Method) and Expect(mCode, mNext, '(') then
      begin
        mSite := Default(TAtlasAsyncSite);
        mSite.FileName := AFileName;
        mSite.Kind := mCall.Kind;
        mSite.Line := LineOf(mCode, mStart);
        mSite.EndLine := LineOf(mCode, ClosingParen(mCode, mNext));
        Result := Result + [mSite];
        Break;
      end;
    end;
  end;
end;

class function TAtlasAsyncSites.SiteAt(const ASites: TAtlasAsyncSiteList; const AFileName: string;
  ALine: Integer): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to High(ASites) do
  begin
    if ASites[mIndex].Contains(ALine) and SameText(ASites[mIndex].FileName, AFileName) and
      ((Result < 0) or (ASites[mIndex].Line >= ASites[Result].Line)) then
    begin
      Result := mIndex;
    end;
  end;
end;

class function TAtlasAsyncSites.SiteOnLine(const ASites: TAtlasAsyncSiteList; const AFileName: string;
  ALine: Integer): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to High(ASites) do
  begin
    if (ASites[mIndex].Line = ALine) and SameText(ASites[mIndex].FileName, AFileName) then
    begin
      Exit(mIndex);
    end;
  end;
end;

class function TAtlasAsyncSites.IsAnonymous(const AHeader: string): Boolean;
var
  mHeader: string;
begin
  mHeader := AHeader.ToLower;
  Result := (Pos('$body', mHeader) > 0) or (Pos('$actrec', mHeader) > 0);
end;

class function TAtlasAsyncSites.OriginFrame(const ASites: TAtlasAsyncSiteList; const AFrames: TAtlasDebugFrames;
  out ASite: Integer): Integer;
var
  mIndex: Integer;
begin
  ASite := -1;
  for mIndex := 0 to High(AFrames) do
  begin
    if AFrames[mIndex].HasSource and IsAnonymous(AFrames[mIndex].Header) then
    begin
      ASite := SiteAt(ASites, AFrames[mIndex].FileName, AFrames[mIndex].Line);
      if ASite >= 0 then
      begin
        Exit(mIndex);
      end;
    end;
  end;
  Result := -1;
end;

{ TAtlasAsyncOrigins }

function TAtlasAsyncOrigins.CountOf(ASite: Integer): Integer;
var
  mEntry: TAtlasAsyncEntry;
begin
  Result := 0;
  for mEntry in FEntries do
  begin
    if mEntry.Site = ASite then
    begin
      Inc(Result);
    end;
  end;
end;

function TAtlasAsyncOrigins.OldestOf(ASite: Integer): Integer;
var
  mIndex: Integer;
begin
  // Einträge stehen in der Reihenfolge des Merkens: der erste der Stelle ist der älteste.
  for mIndex := 0 to High(FEntries) do
  begin
    if FEntries[mIndex].Site = ASite then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

procedure TAtlasAsyncOrigins.Add(ASite: Integer; AThreadId: Cardinal; AAddress: UInt64;
  const AFrames: TAtlasDebugFrames);
var
  mEntry: TAtlasAsyncEntry;
begin
  Inc(FSequence);
  mEntry := Default(TAtlasAsyncEntry);
  mEntry.Site := ASite;
  mEntry.ThreadId := AThreadId;
  mEntry.Address := AAddress;
  mEntry.Frames := AFrames;
  mEntry.Sequence := FSequence;
  FEntries := FEntries + [mEntry];
  while (MaxPerSite > 0) and (CountOf(ASite) > MaxPerSite) do
  begin
    Delete(FEntries, OldestOf(ASite), 1);
  end;
end;

function TAtlasAsyncOrigins.Take(ASite: Integer; AAddress: UInt64; out AEntry: TAtlasAsyncEntry): Boolean;
var
  mIndex, mFound: Integer;
begin
  AEntry := Default(TAtlasAsyncEntry);
  mFound := -1;
  if AAddress <> 0 then
  begin
    for mIndex := High(FEntries) downto 0 do
    begin
      if (FEntries[mIndex].Site = ASite) and (FEntries[mIndex].Address = AAddress) then
      begin
        mFound := mIndex;
        Break;
      end;
    end;
  end;
  if mFound < 0 then
  begin
    mFound := OldestOf(ASite);
  end;
  Result := mFound >= 0;
  if Result then
  begin
    AEntry := FEntries[mFound];
    Delete(FEntries, mFound, 1);
  end;
end;

function TAtlasAsyncOrigins.Count: Integer;
begin
  Result := Length(FEntries);
end;

procedure TAtlasAsyncOrigins.Clear;
begin
  FEntries := nil;
end;

end.
