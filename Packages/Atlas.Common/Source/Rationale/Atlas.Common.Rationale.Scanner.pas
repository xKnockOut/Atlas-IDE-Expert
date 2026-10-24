unit Atlas.Common.Rationale.Scanner;

// Findet Begründungen (#1123) in den Kommentar-Token des Lexers und ordnet sie
// zu (Format in Atlas.Common.Rationale.Contract):
//   - Above: Kommentare direkt über einer Deklaration. Zwischen Kommentar und
//     Deklaration (und zwischen zwei Kommentaren) steht höchstens eine
//     Leerzeile; Attribute und XMLDoc (///) dazwischen stören nicht. Ein
//     Kommentar hinter Code in derselben Zeile gehört zu diesem Code.
//   - ForNode: dazu bei Routinen mit Rumpf alle Begründungen zwischen Kopf und
//     end (lokale Deklarationen und Anweisungen).
//   - ForUnit: Begründungen vom Dateianfang bis zum ersten type-Abschnitt im
//     interface, die keiner Deklaration gehören.
// Folgezeilen: Ein Zeilenkommentar direkt in der nächsten Zeile, dessen Text
// mit mindestens zwei Leerzeichen (oder einem Tabulator) eingerückt ist,
// setzt den Eintrag fort:
//   // WHY: Delphi 12 kennt keinen
//   //      if-Ausdruck.
// Ein Blockkommentar ist immer ein Eintrag. Strings und Direktiven zählen nie.

interface

uses
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Rationale.Contract;

type
  TRationaleScanner = class
  public
    /// <summary>Inhalt eines Kommentar-Tokens ohne //, { } bzw. (* *).</summary>
    class function CommentBody(const AComment: string): string; static;
    /// <summary>Marke (in Großbuchstaben) und Text aus dem Inhalt eines Kommentars; False ohne mögliche Marke.
    /// Eine Marke ist ein Wort aus 2 bis 20 Buchstaben mit Doppelpunkt dahinter oder in Großbuchstaben mit
    /// Leerraum bzw. Kommentarende dahinter. AText darf leer sein (Text in Folgezeilen).</summary>
    class function ParseBody(const ABody: string; out AMarker, AText: string): Boolean; static;
    /// <summary>Begründungen der Kommentare, die in [AFrom, ATo) beginnen.</summary>
    class function InRange(const ATokens: TArray<TPascalToken>; AFrom, ATo: Integer): TArray<TRationaleEntry>;
      static;
    /// <summary>Begründungen direkt über der Deklaration, die an AOffset beginnt.</summary>
    class function Above(const ATokens: TArray<TPascalToken>; AOffset: Integer): TArray<TRationaleEntry>; static;
    /// <summary>Above und bei Routinen mit Rumpf die Begründungen darin.</summary>
    class function ForNode(const ATokens: TArray<TPascalToken>; ANode: TSyntaxNode): TArray<TRationaleEntry>;
      static;
    /// <summary>Begründungen der Unit (ARoot ist die Wurzel des Baums zu ATokens); leer bei program, library und
    /// package.</summary>
    class function ForUnit(const ATokens: TArray<TPascalToken>; ARoot: TSyntaxNode): TArray<TRationaleEntry>;
      overload; static;
    class function ForUnit(ATree: TSyntaxTree): TArray<TRationaleEntry>; overload; static;
  end;

implementation

uses
  System.SysUtils;

const
  cMaxMarkerLength = 20;

function IsSpace(ACh: Char): Boolean;
begin
  Result := (ACh = ' ') or (ACh = #9) or (ACh = #10) or (ACh = #13);
end;

function IsLetter(ACh: Char): Boolean;
begin
  Result := CharInSet(ACh, ['A'..'Z', 'a'..'z']);
end;

/// <summary>Leerraum (auch Zeilenumbrüche) zu je einem Leerzeichen, außen ohne.</summary>
function Collapse(const AText: string): string;
var
  mIndex: Integer;
  mPending: Boolean;
begin
  Result := '';
  mPending := False;
  for mIndex := 1 to Length(AText) do
    if IsSpace(AText[mIndex]) then
      mPending := Result <> ''
    else
    begin
      if mPending then
        Result := Result + ' ';
      mPending := False;
      Result := Result + AText[mIndex];
    end;
end;

function IsLineComment(const AToken: TPascalToken): Boolean;
begin
  Result := (AToken.Kind = TPascalTokenKind.Comment) and (Copy(AToken.Text, 1, 2) = '//');
end;

function IsDocComment(const AToken: TPascalToken): Boolean;
begin
  Result := (AToken.Kind = TPascalTokenKind.Comment) and (Copy(AToken.Text, 1, 3) = '///');
end;

/// <summary>Erstes Token, das bei AOffset oder dahinter beginnt; Length(ATokens) ohne.</summary>
function TokenIndexAt(const ATokens: TArray<TPascalToken>; AOffset: Integer): Integer;
var
  mLow, mHigh, mMiddle: Integer;
begin
  mLow := 0;
  mHigh := Length(ATokens);
  while mLow < mHigh do
  begin
    mMiddle := (mLow + mHigh) div 2;
    if ATokens[mMiddle].Offset < AOffset then
      mLow := mMiddle + 1
    else
      mHigh := mMiddle;
  end;
  Result := mLow;
end;

/// <summary>Einträge aus den Kommentar-Token AIndices (aufsteigend): Kommentare mit Marke beginnen einen
/// Eintrag, eingerückte Zeilenkommentare direkt darunter setzen ihn fort.</summary>
function FromComments(const ATokens: TArray<TPascalToken>; const AIndices: TArray<Integer>): TArray<TRationaleEntry>;
var
  mOpen, mContinues: Boolean;
  mEntry: TRationaleEntry;
  mLastIndex, mLastLine, mPosition: Integer;
  mToken: TPascalToken;
  mBody, mMarker, mText: string;

  procedure Flush;
  begin
    if mOpen then
    begin
      mEntry.Text := Collapse(mEntry.Text);
      if Length(mEntry.Text) > TRationale.MaxText then
        mEntry.Text := Copy(mEntry.Text, 1, TRationale.MaxText - 1) + '…';
      if mEntry.Text <> '' then
        Result := Result + [mEntry];
    end;
    mOpen := False;
  end;

begin
  Result := nil;
  mOpen := False;
  mContinues := False;
  mLastIndex := -2;
  mLastLine := -2;
  for mPosition := 0 to High(AIndices) do
  begin
    mToken := ATokens[AIndices[mPosition]];
    if IsDocComment(mToken) then
    begin
      Flush;
      Continue;
    end;
    mBody := TRationaleScanner.CommentBody(mToken.Text);
    if mOpen and mContinues and IsLineComment(mToken) and (AIndices[mPosition] = mLastIndex + 1) and
      (mToken.StartPos.Line = mLastLine + 1) and ((Copy(mBody, 1, 2) = '  ') or (Copy(mBody, 1, 1) = #9)) then
    begin
      mEntry.Text := mEntry.Text + ' ' + mBody;
      mLastIndex := AIndices[mPosition];
      mLastLine := mToken.EndPos.Line;
      Continue;
    end;
    Flush;
    if TRationaleScanner.ParseBody(mBody, mMarker, mText) then
    begin
      mEntry := TRationaleEntry.Create(mMarker, mText, mToken.StartPos.Line);
      mOpen := True;
      mContinues := IsLineComment(mToken);
      mLastIndex := AIndices[mPosition];
      mLastLine := mToken.EndPos.Line;
    end;
  end;
  Flush;
end;

{ TRationaleScanner }

class function TRationaleScanner.CommentBody(const AComment: string): string;
var
  mFirst, mLast: Integer;
begin
  mFirst := 1;
  mLast := Length(AComment);
  if Copy(AComment, 1, 2) = '//' then
    mFirst := 3
  else if Copy(AComment, 1, 2) = '(*' then
  begin
    mFirst := 3;
    if (mLast >= 4) and (Copy(AComment, mLast - 1, 2) = '*)') then
      Dec(mLast, 2);
  end
  else if Copy(AComment, 1, 1) = '{' then
  begin
    mFirst := 2;
    if (mLast >= 2) and (AComment[mLast] = '}') then
      Dec(mLast);
  end;
  Result := Copy(AComment, mFirst, mLast - mFirst + 1);
end;

class function TRationaleScanner.ParseBody(const ABody: string; out AMarker, AText: string): Boolean;
var
  mPosition, mStart, mAfter: Integer;
  mWord: string;
begin
  Result := False;
  AMarker := '';
  AText := '';
  mPosition := 1;
  while (mPosition <= Length(ABody)) and IsSpace(ABody[mPosition]) do
    Inc(mPosition);
  mStart := mPosition;
  while (mPosition <= Length(ABody)) and IsLetter(ABody[mPosition]) do
    Inc(mPosition);
  mWord := Copy(ABody, mStart, mPosition - mStart);
  if (Length(mWord) < 2) or (Length(mWord) > cMaxMarkerLength) then
    Exit;
  mAfter := mPosition;
  while (mAfter <= Length(ABody)) and (ABody[mAfter] = ' ') do
    Inc(mAfter);
  if (mAfter <= Length(ABody)) and (ABody[mAfter] = ':') then
    AText := Copy(ABody, mAfter + 1, MaxInt)
  else if (mWord = UpperCase(mWord)) and ((mPosition > Length(ABody)) or IsSpace(ABody[mPosition])) then
    AText := Copy(ABody, mPosition, MaxInt)
  else
    Exit;
  AMarker := UpperCase(mWord);
  AText := Trim(AText);
  Result := True;
end;

class function TRationaleScanner.InRange(const ATokens: TArray<TPascalToken>; AFrom,
  ATo: Integer): TArray<TRationaleEntry>;
var
  mIndex: Integer;
  mIndices: TArray<Integer>;
begin
  mIndices := nil;
  mIndex := TokenIndexAt(ATokens, AFrom);
  while (mIndex < Length(ATokens)) and (ATokens[mIndex].Offset < ATo) do
  begin
    if ATokens[mIndex].Kind = TPascalTokenKind.Comment then
      mIndices := mIndices + [mIndex];
    Inc(mIndex);
  end;
  Result := FromComments(ATokens, mIndices);
end;

class function TRationaleScanner.Above(const ATokens: TArray<TPascalToken>; AOffset: Integer): TArray<TRationaleEntry>;
var
  mIndex, mBoundary, mDepth: Integer;
  mIndices: TArray<Integer>;
begin
  Result := nil;
  mIndex := TokenIndexAt(ATokens, AOffset);
  if mIndex >= Length(ATokens) then
    Exit;
  mBoundary := ATokens[mIndex].StartPos.Line;
  Dec(mIndex);
  // Attribute zwischen Kommentar und Deklaration überspringen.
  while (mIndex >= 0) and ATokens[mIndex].IsSymbol(']') do
  begin
    mDepth := 0;
    repeat
      if ATokens[mIndex].IsSymbol(']') then
        Inc(mDepth)
      else if ATokens[mIndex].IsSymbol('[') then
        Dec(mDepth);
      Dec(mIndex);
    until (mIndex < 0) or (mDepth = 0);
    if mIndex >= -1 then
      mBoundary := ATokens[mIndex + 1].StartPos.Line;
  end;
  mIndices := nil;
  while (mIndex >= 0) and (ATokens[mIndex].Kind = TPascalTokenKind.Comment) do
  begin
    // Höchstens eine Leerzeile; ein Kommentar hinter Code gehört zum Code.
    if mBoundary - ATokens[mIndex].EndPos.Line > 2 then
      Break;
    if (mIndex > 0) and (ATokens[mIndex - 1].Kind <> TPascalTokenKind.Comment) and
      (ATokens[mIndex - 1].EndPos.Line = ATokens[mIndex].StartPos.Line) then
      Break;
    mIndices := [mIndex] + mIndices;
    mBoundary := ATokens[mIndex].StartPos.Line;
    Dec(mIndex);
  end;
  Result := FromComments(ATokens, mIndices);
end;

class function TRationaleScanner.ForNode(const ATokens: TArray<TPascalToken>; ANode: TSyntaxNode): TArray<TRationaleEntry>;
var
  mHeader: TSyntaxNode;
begin
  Result := Above(ATokens, ANode.StartOffset);
  if (ANode.Kind = TSyntaxKind.RoutineDecl) and (ANode.FindChild(TSyntaxKind.Block) <> nil) then
  begin
    mHeader := ANode.FindChild(TSyntaxKind.RoutineHeader);
    if mHeader <> nil then
      Result := Result + InRange(ATokens, mHeader.EndOffset, ANode.EndOffset)
    else
      Result := Result + InRange(ATokens, ANode.StartOffset + 1, ANode.EndOffset);
  end;
end;

class function TRationaleScanner.ForUnit(ATree: TSyntaxTree): TArray<TRationaleEntry>;
begin
  Result := nil;
  if ATree <> nil then
    Result := ForUnit(ATree.Tokens, ATree.Root);
end;

class function TRationaleScanner.ForUnit(const ATokens: TArray<TPascalToken>;
  ARoot: TSyntaxNode): TArray<TRationaleEntry>;
var
  mInterface, mChild, mDecl: TSyntaxNode;
  mLimit, mIndex, mInner: Integer;
  mTaken: TArray<Integer>;
  mEntry: TRationaleEntry;
  mAll: TArray<TRationaleEntry>;

  procedure Take(ANode: TSyntaxNode);
  var
    mOwn: TRationaleEntry;
  begin
    for mOwn in Above(ATokens, ANode.StartOffset) do
      mTaken := mTaken + [mOwn.Line];
  end;

  function IsTaken(ALine: Integer): Boolean;
  var
    mLine: Integer;
  begin
    for mLine in mTaken do
      if mLine = ALine then
        Exit(True);
    Result := False;
  end;

begin
  Result := nil;
  if (ARoot = nil) or (ARoot.Kind <> TSyntaxKind.UnitFile) then
    Exit;
  mInterface := ARoot.FindChild(TSyntaxKind.InterfaceSection);
  if mInterface = nil then
    Exit;
  mLimit := mInterface.EndOffset;
  mTaken := nil;
  for mIndex := 0 to mInterface.ChildCount - 1 do
  begin
    mChild := mInterface[mIndex];
    if mChild.Kind = TSyntaxKind.TypeSection then
    begin
      mLimit := mChild.StartOffset;
      Break;
    end;
    if mChild.Kind in [TSyntaxKind.ConstSection, TSyntaxKind.VarSection] then
      for mInner := 0 to mChild.ChildCount - 1 do
      begin
        mDecl := mChild[mInner];
        Take(mDecl);
      end
    else if mChild.Kind = TSyntaxKind.RoutineDecl then
      Take(mChild);
  end;
  mAll := InRange(ATokens, 0, mLimit);
  for mEntry in mAll do
    if not IsTaken(mEntry.Line) then
      Result := Result + [mEntry];
end;

end.
