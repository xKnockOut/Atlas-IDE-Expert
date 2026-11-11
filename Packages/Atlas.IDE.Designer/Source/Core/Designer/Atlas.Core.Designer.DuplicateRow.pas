unit Atlas.Core.Designer.DuplicateRow;

// Auswahl im Designer in Reihe duplizieren (#736), ohne VCL und Windows:
// - Liste „Fax, Mobil, Privat“ (Komma oder Semikolon) ergibt die Anzahl der
//   Kopien, sonst die angegebene Anzahl.
// - Lage: die Auswahl als Block, je Kopie um Höhe (nach unten) bzw. Breite
//   (nach rechts) plus Abstand weiter. Abstand ohne Vorgabe: der kleinste zu
//   einem Nachbarn darüber oder darunter (bzw. links oder rechts), der den
//   Block quer zur Richtung überlappt.
// - Namen: mit Liste Präfix des Originals (Kleinbuchstaben vor dem ersten
//   Großbuchstaben, „lbl“ in lblTelefon; ohne Präfix der Name ohne Zahl am
//   Ende) plus Listeneintrag als Bezeichner; ohne Liste der Name mit
//   hochgezählter Zahl (edtTelefon2, Edit4). Vergebene Namen werden
//   übersprungen.
// - Captions: mit Liste der Eintrag, mit Doppelpunkt, wenn das Original einen
//   hat; ohne Liste unverändert.
// - TabOrder: Kopien hinter dem Original, je Kopie in der Folge des Originals.
// - Überlauf: Kopie ragt aus dem Elternelement oder überdeckt ein anderes
//   Steuerelement. Mit „Nachfolgende verschieben“ rücken die Steuerelemente
//   hinter dem Block um die Fläche aller Kopien weiter.

interface

uses
  System.Types;

type
{$SCOPEDENUMS ON}
  TAtlasDuplicateDirection = (Down, Right);
{$SCOPEDENUMS OFF}

  /// <summary>Eingabe der Lageberechnung.</summary>
  TAtlasDuplicateRequest = record
    /// <summary>Umriss der Auswahl (alle markierten zusammen).</summary>
    Group: TRect;
    /// <summary>Innenfläche des Elternelements.</summary>
    Client: TRect;
    /// <summary>Übrige Steuerelemente im selben Elternelement.</summary>
    Others: TArray<TRect>;
    Direction: TAtlasDuplicateDirection;
    Gap: Integer;
    Count: Integer;
    /// <summary>Nachfolgende Steuerelemente verschieben.</summary>
    Push: Boolean;
  end;

  TAtlasDuplicateLayout = record
    /// <summary>Umriss je Kopie.</summary>
    Copies: TArray<TRect>;
    /// <summary>Kopie ragt heraus oder überdeckt ein anderes Steuerelement.</summary>
    Bad: TArray<Boolean>;
    /// <summary>Übrige Steuerelemente nach dem Verschieben (wie Others ohne Push).</summary>
    Others: TArray<TRect>;
    function AnyBad: Boolean;
  end;

  TAtlasDuplicateRow = class
  public
    /// <summary>Einträge der Liste, getrimmt, leere fallen weg.</summary>
    class function ParseList(const AText: string): TArray<string>; static;
    /// <summary>Anzahl der Kopien: Länge der Liste, sonst ACount (mindestens 1).</summary>
    class function CopyCount(const AList: TArray<string>; ACount: Integer): Integer; static;
    /// <summary>Umriss aller Rechtecke.</summary>
    class function UnionOf(const ARects: TArray<TRect>): TRect; static;
    /// <summary>Kleinster Abstand zu einem Nachbarn in Richtung ADirection (davor oder dahinter); -1 = keiner.</summary>
    class function DetectGap(const AGroup: TRect; const AOthers: TArray<TRect>;
      ADirection: TAtlasDuplicateDirection): Integer; static;
    /// <summary>Verschiebung der Kopie AIndex (ab 0) gegenüber dem Original.</summary>
    class function Offset(const AGroup: TRect; ADirection: TAtlasDuplicateDirection; AGap, AIndex: Integer): TPoint;
      static;
    class function Layout(const ARequest: TAtlasDuplicateRequest): TAtlasDuplicateLayout; static;
    /// <summary>Indizes der Steuerelemente hinter dem Block (darunter bzw. rechts davon).</summary>
    class function Followers(const AGroup: TRect; const AOthers: TArray<TRect>;
      ADirection: TAtlasDuplicateDirection): TArray<Integer>; static;
    /// <summary>Kleinbuchstaben vor dem ersten Großbuchstaben („lbl“ in lblTelefon); '' = keins.</summary>
    class function PrefixOf(const AName: string): string; static;
    /// <summary>Listeneintrag als Bezeichner: Wörter groß beginnend zusammen, Umlaute umschrieben.</summary>
    class function Identifier(const AEntry: string): string; static;
    /// <summary>Name der Kopie AIndex (ab 0); AEntry = '' zählt hoch.</summary>
    class function NameFor(const AName, AEntry: string; AIndex: Integer): string; static;
    /// <summary>AName oder mit höherer Zahl am Ende, bis er nicht in ATaken steht (Groß/klein egal).</summary>
    class function UniqueName(const AName: string; const ATaken: TArray<string>): string; static;
    /// <summary>Namen [Kopie][Steuerelement], eindeutig gegen ATaken und untereinander.</summary>
    class function Names(const ANames, AEntries: TArray<string>; ACount: Integer;
      const ATaken: TArray<string>): TArray<TArray<string>>; static;
    /// <summary>Caption der Kopie: AEntry (mit Doppelpunkt wie im Original); AEntry = '' lässt ACaption.</summary>
    class function CaptionFor(const ACaption, AEntry: string): string; static;
    /// <summary>TabOrder je Kopie und fokussierbarem Steuerelement, hinter AAfter.</summary>
    class function TabOrders(AAfter, AWinCount, ACount: Integer): TArray<TArray<Integer>>; static;
    /// <summary>Verweis in der Kopie: zeigt ein Original auf ein anderes der Auswahl (FocusControl), dann auf
    /// dessen Kopie; sonst bleibt der Verweis.</summary>
    class function MapReference(const ATarget: string; const AOriginals, ACopies: TArray<string>): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.Math;

{ TAtlasDuplicateLayout }

function TAtlasDuplicateLayout.AnyBad: Boolean;
var
  mBad: Boolean;
begin
  for mBad in Bad do
  begin
    if mBad then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

{ TAtlasDuplicateRow }

class function TAtlasDuplicateRow.ParseList(const AText: string): TArray<string>;
var
  mPart: string;
begin
  Result := nil;
  for mPart in AText.Split([',', ';']) do
  begin
    if Trim(mPart) <> '' then
    begin
      Result := Result + [Trim(mPart)];
    end;
  end;
end;

class function TAtlasDuplicateRow.CopyCount(const AList: TArray<string>; ACount: Integer): Integer;
begin
  Result := Length(AList);
  if Result = 0 then
  begin
    Result := ACount;
  end;
  if Result < 1 then
  begin
    Result := 1;
  end;
end;

class function TAtlasDuplicateRow.UnionOf(const ARects: TArray<TRect>): TRect;
var
  mIndex: Integer;
begin
  Result := Rect(0, 0, 0, 0);
  for mIndex := 0 to High(ARects) do
  begin
    if mIndex = 0 then
    begin
      Result := ARects[0];
    end
    else
    begin
      Result.Left := Min(Result.Left, ARects[mIndex].Left);
      Result.Top := Min(Result.Top, ARects[mIndex].Top);
      Result.Right := Max(Result.Right, ARects[mIndex].Right);
      Result.Bottom := Max(Result.Bottom, ARects[mIndex].Bottom);
    end;
  end;
end;

/// <summary>Überlappen sich A und B quer zur Richtung (waagrecht bei Down)?</summary>
function Across(const A, B: TRect; ADirection: TAtlasDuplicateDirection): Boolean;
begin
  if ADirection = TAtlasDuplicateDirection.Down then
  begin
    Result := (A.Left < B.Right) and (B.Left < A.Right);
  end
  else
  begin
    Result := (A.Top < B.Bottom) and (B.Top < A.Bottom);
  end;
end;

/// <summary>Abstand von AGroup zu AOther in Richtung (davor oder dahinter); -1 bei Überlappung.</summary>
function DistanceTo(const AGroup, AOther: TRect; ADirection: TAtlasDuplicateDirection): Integer;
begin
  Result := -1;
  if ADirection = TAtlasDuplicateDirection.Down then
  begin
    if AOther.Top >= AGroup.Bottom then
    begin
      Result := AOther.Top - AGroup.Bottom;
    end
    else if AOther.Bottom <= AGroup.Top then
    begin
      Result := AGroup.Top - AOther.Bottom;
    end;
  end
  else if AOther.Left >= AGroup.Right then
  begin
    Result := AOther.Left - AGroup.Right;
  end
  else if AOther.Right <= AGroup.Left then
  begin
    Result := AGroup.Left - AOther.Right;
  end;
end;

class function TAtlasDuplicateRow.DetectGap(const AGroup: TRect; const AOthers: TArray<TRect>;
  ADirection: TAtlasDuplicateDirection): Integer;
var
  mOther: TRect;
  mDistance: Integer;
begin
  Result := -1;
  for mOther in AOthers do
  begin
    if not Across(AGroup, mOther, ADirection) then
    begin
      Continue;
    end;
    mDistance := DistanceTo(AGroup, mOther, ADirection);
    if (mDistance >= 0) and ((Result < 0) or (mDistance < Result)) then
    begin
      Result := mDistance;
    end;
  end;
end;

class function TAtlasDuplicateRow.Offset(const AGroup: TRect; ADirection: TAtlasDuplicateDirection;
  AGap, AIndex: Integer): TPoint;
begin
  if ADirection = TAtlasDuplicateDirection.Down then
  begin
    Result := Point(0, (AGroup.Height + AGap) * (AIndex + 1));
  end
  else
  begin
    Result := Point((AGroup.Width + AGap) * (AIndex + 1), 0);
  end;
end;

class function TAtlasDuplicateRow.Followers(const AGroup: TRect; const AOthers: TArray<TRect>;
  ADirection: TAtlasDuplicateDirection): TArray<Integer>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to High(AOthers) do
  begin
    if ((ADirection = TAtlasDuplicateDirection.Down) and (AOthers[mIndex].Top >= AGroup.Bottom)) or
      ((ADirection = TAtlasDuplicateDirection.Right) and (AOthers[mIndex].Left >= AGroup.Right)) then
    begin
      Result := Result + [mIndex];
    end;
  end;
end;

function Overlaps(const A, B: TRect): Boolean;
begin
  Result := (A.Left < B.Right) and (B.Left < A.Right) and (A.Top < B.Bottom) and (B.Top < A.Bottom);
end;

function Inside(const ARect, AClient: TRect): Boolean;
begin
  Result := (ARect.Left >= AClient.Left) and (ARect.Top >= AClient.Top) and (ARect.Right <= AClient.Right) and
    (ARect.Bottom <= AClient.Bottom);
end;

/// <summary>Übrige nach dem Verschieben der Nachfolgenden um die Fläche aller Kopien.</summary>
function Pushed(const ARequest: TAtlasDuplicateRequest): TArray<TRect>;
var
  mIndex: Integer;
  mShift: TPoint;
begin
  Result := Copy(ARequest.Others);
  if not ARequest.Push then
  begin
    Exit;
  end;
  mShift := TAtlasDuplicateRow.Offset(ARequest.Group, ARequest.Direction, ARequest.Gap, ARequest.Count - 1);
  for mIndex in TAtlasDuplicateRow.Followers(ARequest.Group, ARequest.Others, ARequest.Direction) do
  begin
    Result[mIndex].Offset(mShift);
  end;
end;

class function TAtlasDuplicateRow.Layout(const ARequest: TAtlasDuplicateRequest): TAtlasDuplicateLayout;
var
  mIndex: Integer;
  mRect, mOther: TRect;
  mBad: Boolean;
begin
  Result.Copies := nil;
  Result.Bad := nil;
  Result.Others := Pushed(ARequest);
  for mIndex := 0 to ARequest.Count - 1 do
  begin
    mRect := ARequest.Group;
    mRect.Offset(Offset(ARequest.Group, ARequest.Direction, ARequest.Gap, mIndex));
    mBad := not Inside(mRect, ARequest.Client);
    for mOther in Result.Others do
    begin
      mBad := mBad or Overlaps(mRect, mOther);
    end;
    Result.Copies := Result.Copies + [mRect];
    Result.Bad := Result.Bad + [mBad];
  end;
end;

function IsLower(AChar: Char): Boolean;
begin
  Result := CharInSet(AChar, ['a'..'z']);
end;

function IsUpper(AChar: Char): Boolean;
begin
  Result := CharInSet(AChar, ['A'..'Z']);
end;

function IsDigit(AChar: Char): Boolean;
begin
  Result := CharInSet(AChar, ['0'..'9']);
end;

class function TAtlasDuplicateRow.PrefixOf(const AName: string): string;
var
  mIndex: Integer;
begin
  mIndex := 1;
  while (mIndex <= Length(AName)) and IsLower(AName[mIndex]) do
  begin
    Inc(mIndex);
  end;
  Result := '';
  if (mIndex > 1) and (mIndex <= Length(AName)) and IsUpper(AName[mIndex]) then
  begin
    Result := Copy(AName, 1, mIndex - 1);
  end;
end;

/// <summary>Umlaute und ß als Buchstabenfolge; sonst das Zeichen, wenn es in einen Bezeichner passt.</summary>
function Spell(AChar: Char): string;
begin
  case AChar of
    #$E4:
      Result := 'ae';
    #$F6:
      Result := 'oe';
    #$FC:
      Result := 'ue';
    #$C4:
      Result := 'Ae';
    #$D6:
      Result := 'Oe';
    #$DC:
      Result := 'Ue';
    #$DF:
      Result := 'ss';
  else
    Result := '';
    if IsLower(AChar) or IsUpper(AChar) or IsDigit(AChar) or (AChar = '_') then
    begin
      Result := AChar;
    end;
  end;
end;

class function TAtlasDuplicateRow.Identifier(const AEntry: string): string;
var
  mChar: Char;
  mPart: string;
  mStart: Boolean;
begin
  Result := '';
  mStart := True;
  for mChar in AEntry do
  begin
    mPart := Spell(mChar);
    if mPart = '' then
    begin
      mStart := True;
      Continue;
    end;
    if mStart then
    begin
      mPart := UpperCase(Copy(mPart, 1, 1)) + Copy(mPart, 2, MaxInt);
      mStart := False;
    end;
    Result := Result + mPart;
  end;
end;

/// <summary>Name ohne Zahl am Ende und die Zahl (-1 = keine).</summary>
function SplitNumber(const AName: string; out ANumber: Integer): string;
var
  mIndex: Integer;
begin
  mIndex := Length(AName);
  while (mIndex > 0) and IsDigit(AName[mIndex]) do
  begin
    Dec(mIndex);
  end;
  Result := Copy(AName, 1, mIndex);
  ANumber := StrToIntDef(Copy(AName, mIndex + 1, 9), -1);
  if mIndex = Length(AName) then
  begin
    ANumber := -1;
  end;
end;

class function TAtlasDuplicateRow.NameFor(const AName, AEntry: string; AIndex: Integer): string;
var
  mStem, mPrefix: string;
  mNumber: Integer;
begin
  mStem := SplitNumber(AName, mNumber);
  if Identifier(AEntry) <> '' then
  begin
    mPrefix := PrefixOf(AName);
    if mPrefix = '' then
    begin
      mPrefix := mStem;
    end;
    Exit(mPrefix + Identifier(AEntry));
  end;
  if mNumber < 0 then
  begin
    mNumber := 1;
  end;
  Result := mStem + IntToStr(mNumber + AIndex + 1);
end;

function Taken(const AName: string; const ATaken: TArray<string>): Boolean;
var
  mName: string;
begin
  for mName in ATaken do
  begin
    if SameText(mName, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasDuplicateRow.UniqueName(const AName: string; const ATaken: TArray<string>): string;
var
  mStem: string;
  mNumber: Integer;
begin
  Result := AName;
  if not Taken(Result, ATaken) then
  begin
    Exit;
  end;
  mStem := SplitNumber(AName, mNumber);
  if mNumber < 1 then
  begin
    mNumber := 1;
  end;
  repeat
    Inc(mNumber);
    Result := mStem + IntToStr(mNumber);
  until not Taken(Result, ATaken);
end;

class function TAtlasDuplicateRow.Names(const ANames, AEntries: TArray<string>; ACount: Integer;
  const ATaken: TArray<string>): TArray<TArray<string>>;
var
  mCopy, mControl: Integer;
  mEntry, mName: string;
  mTaken: TArray<string>;
begin
  mTaken := Copy(ATaken);
  SetLength(Result, ACount);
  for mCopy := 0 to ACount - 1 do
  begin
    mEntry := '';
    if mCopy < Length(AEntries) then
    begin
      mEntry := AEntries[mCopy];
    end;
    SetLength(Result[mCopy], Length(ANames));
    for mControl := 0 to High(ANames) do
    begin
      mName := UniqueName(NameFor(ANames[mControl], mEntry, mCopy), mTaken);
      Result[mCopy][mControl] := mName;
      mTaken := mTaken + [mName];
    end;
  end;
end;

class function TAtlasDuplicateRow.CaptionFor(const ACaption, AEntry: string): string;
begin
  Result := ACaption;
  if AEntry = '' then
  begin
    Exit;
  end;
  Result := AEntry;
  if TrimRight(ACaption).EndsWith(':') then
  begin
    Result := Result + ':';
  end;
end;

class function TAtlasDuplicateRow.TabOrders(AAfter, AWinCount, ACount: Integer): TArray<TArray<Integer>>;
var
  mCopy, mControl: Integer;
begin
  SetLength(Result, ACount);
  for mCopy := 0 to ACount - 1 do
  begin
    SetLength(Result[mCopy], AWinCount);
    for mControl := 0 to AWinCount - 1 do
    begin
      Result[mCopy][mControl] := AAfter + 1 + mCopy * AWinCount + mControl;
    end;
  end;
end;

class function TAtlasDuplicateRow.MapReference(const ATarget: string; const AOriginals,
  ACopies: TArray<string>): string;
var
  mIndex: Integer;
begin
  Result := ATarget;
  for mIndex := 0 to High(AOriginals) do
  begin
    if (mIndex <= High(ACopies)) and SameText(AOriginals[mIndex], ATarget) then
    begin
      Exit(ACopies[mIndex]);
    end;
  end;
end;

end.
