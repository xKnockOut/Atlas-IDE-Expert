unit Atlas.Core.Designer.ButtonBar;

// Knopfleiste im Designer anordnen (#732), ohne VCL und Windows:
// - Rolle je Knopf aus ModalResult (mrOk/mrYes → ok, mrCancel/mrNo →
//   cancel), sonst aus Caption (ohne „&amp;“) und Name, Groß- und
//   Kleinschreibung egal. Die Begriffe gibt der Aufrufer: eigene aus
//   designer.buttonBar.roles („ok=Weiter|Los; cancel=Zurück“) vor den
//   Beschriftungen beider Sprachen (Sprachtabelle); die Komponentennamen
//   (btnOk …) stehen hier.
// - Reihenfolge nach designer.buttonBar.order, „other“ vor help in der
//   bisherigen Reihenfolge.
// - Lage unten rechts, unten links, rechts oben oder rechts unten (senkrecht)
//   mit Abstand zum Rand und untereinander; Anchors passend zur Lage.
// - Erkennt Handler, die ModalResult selbst setzen oder Close aufrufen: dort
//   setzt Atlas kein ModalResult.

interface

uses
  System.Types;

type
{$SCOPEDENUMS ON}
  TAtlasButtonRole = (Other, Ok, Cancel, Apply, Help);
  TAtlasButtonBarPosition = (BottomRight, BottomLeft, RightTop, RightBottom);
  TAtlasButtonAnchor = (Left, Top, Right, Bottom);
{$SCOPEDENUMS OFF}
  TAtlasButtonAnchors = set of TAtlasButtonAnchor;

  TAtlasButtonBar = class
  public const
    /// <summary>ModalResult-Werte der VCL.</summary>
    cMrOk = 1;
    cMrCancel = 2;
    cMrYes = 6;
    cMrNo = 7;
    cDefaultOrder = 'ok,cancel,apply,help';
  public
    /// <summary>Rolle nach ModalResult, dann nach ATerms („ok=OK|Speichern; cancel=Abbrechen“, eigene zuerst,
    /// dann die Beschriftungen beider Sprachen) und den eingebauten Komponentennamen.</summary>
    class function RoleOf(const AName, ACaption: string; AModalResult: Integer; const ATerms: string): TAtlasButtonRole;
      static;
    /// <summary>Rolle aus ihrem Namen (ok, cancel, apply, help, other); False bei unbekanntem.</summary>
    class function TryParseRole(const AText: string; out ARole: TAtlasButtonRole): Boolean; static;
    class function RoleName(ARole: TAtlasButtonRole): string; static;
    /// <summary>Position aus bottomRight, bottomLeft, rightTop, rightBottom; sonst BottomRight.</summary>
    class function PositionOf(const AText: string): TAtlasButtonBarPosition; static;
    /// <summary>Indizes in der neuen Reihenfolge; gleiche Rollen und „other“ behalten ihre bisherige Folge.</summary>
    class function Order(const ARoles: TArray<TAtlasButtonRole>; const AOrder: string): TArray<Integer>; static;
    /// <summary>Lage von ACount Knöpfen der Größe ASize im Rechteck AClient.</summary>
    class function Layout(ACount: Integer; const ASize: TSize; APosition: TAtlasButtonBarPosition; const AClient: TRect;
      AMargin, AGap: Integer): TArray<TRect>; static;
    class function AnchorsOf(APosition: TAtlasButtonBarPosition): TAtlasButtonAnchors; static;
    /// <summary>Häufigste Höhe; bei Gleichstand die zuerst genannte, ohne Höhen 0.</summary>
    class function CommonHeight(const AHeights: TArray<Integer>): Integer; static;
    /// <summary>Setzt der Handler AMethod in ASource ModalResult selbst oder ruft er Close auf?</summary>
    class function HandlerCloses(const ASource, AMethod: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.RegularExpressions;

const
  cRoleNames: array[TAtlasButtonRole] of string = ('other', 'ok', 'cancel', 'apply', 'help');
  cPositionNames: array[TAtlasButtonBarPosition] of string = ('bottomRight', 'bottomLeft', 'rightTop',
    'rightBottom');
  /// <summary>Eingebaute Komponentennamen je Rolle; die Beschriftungen beider Sprachen kommen vom Aufrufer.</summary>
  cNameTerms = 'ok=btnOk|btnSave|btnSpeichern; cancel=btnCancel|btnAbbrechen|btnClose; apply=btnApply|' +
    'btnUebernehmen; help=btnHelp|btnHilfe';

function StripAccel(const AText: string): string;
begin
  Result := StringReplace(StringReplace(AText, '&&', #1, [rfReplaceAll]), '&', '', [rfReplaceAll]);
  Result := StringReplace(Result, #1, '&', [rfReplaceAll]);
end;

/// <summary>Klein geschrieben, auch Ä, Ö und Ü (SameText und LowerCase kennen nur ASCII).</summary>
function Fold(const AText: string): string;
begin
  Result := LowerCase(AText);
  Result := StringReplace(Result, #$C4, #$E4, [rfReplaceAll]);
  Result := StringReplace(Result, #$D6, #$F6, [rfReplaceAll]);
  Result := StringReplace(Result, #$DC, #$FC, [rfReplaceAll]);
end;

function HasTerm(const ATerms, AText: string): Boolean;
var
  mTerm: string;
begin
  if AText = '' then
  begin
    Exit(False);
  end;
  for mTerm in ATerms.Split(['|']) do
  begin
    if Fold(Trim(mTerm)) = Fold(AText) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Rolle aus Begriffen „ok=Weiter|Los; cancel=Zurück“, der erste Treffer zählt; False ohne.</summary>
function CustomRole(const ATerms, AName, ACaption: string; out ARole: TAtlasButtonRole): Boolean;
var
  mEntry, mRole, mList: string;
  mPos: Integer;
begin
  for mEntry in ATerms.Split([';']) do
  begin
    mPos := Pos('=', mEntry);
    if mPos = 0 then
    begin
      Continue;
    end;
    mRole := Trim(Copy(mEntry, 1, mPos - 1));
    mList := Copy(mEntry, mPos + 1, MaxInt);
    if TAtlasButtonBar.TryParseRole(mRole, ARole) and (HasTerm(mList, ACaption) or HasTerm(mList, AName)) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

{ TAtlasButtonBar }

class function TAtlasButtonBar.RoleName(ARole: TAtlasButtonRole): string;
begin
  Result := cRoleNames[ARole];
end;

class function TAtlasButtonBar.TryParseRole(const AText: string; out ARole: TAtlasButtonRole): Boolean;
var
  mRole: TAtlasButtonRole;
begin
  for mRole := Low(TAtlasButtonRole) to High(TAtlasButtonRole) do
  begin
    if SameText(Trim(AText), cRoleNames[mRole]) then
    begin
      ARole := mRole;
      Exit(True);
    end;
  end;
  ARole := TAtlasButtonRole.Other;
  Result := False;
end;

class function TAtlasButtonBar.PositionOf(const AText: string): TAtlasButtonBarPosition;
var
  mPosition: TAtlasButtonBarPosition;
begin
  for mPosition := Low(TAtlasButtonBarPosition) to High(TAtlasButtonBarPosition) do
  begin
    if SameText(AText, cPositionNames[mPosition]) then
    begin
      Exit(mPosition);
    end;
  end;
  Result := TAtlasButtonBarPosition.BottomRight;
end;

class function TAtlasButtonBar.RoleOf(const AName, ACaption: string; AModalResult: Integer;
  const ATerms: string): TAtlasButtonRole;
var
  mCaption: string;
begin
  case AModalResult of
    cMrOk, cMrYes:
      Exit(TAtlasButtonRole.Ok);
    cMrCancel, cMrNo:
      Exit(TAtlasButtonRole.Cancel);
  end;
  // Ganze Begriffe: „Übernehmen“ allein ist apply, „Übernehmen und schließen“ ist ok.
  mCaption := Trim(StripAccel(ACaption));
  if not CustomRole(ATerms + ';' + cNameTerms, AName, mCaption, Result) then
  begin
    Result := TAtlasButtonRole.Other;
  end;
end;

/// <summary>Rang einer Rolle nach AOrder; „other“ unmittelbar vor help bzw. am Ende.</summary>
function Rank(ARole: TAtlasButtonRole; const AOrder: TArray<string>): Integer;
var
  mIndex: Integer;
  mRole: TAtlasButtonRole;
begin
  for mIndex := 0 to High(AOrder) do
  begin
    if TAtlasButtonBar.TryParseRole(AOrder[mIndex], mRole) and (mRole = ARole) then
    begin
      Exit(mIndex * 2);
    end;
  end;
  if ARole = TAtlasButtonRole.Other then
  begin
    Result := Rank(TAtlasButtonRole.Help, AOrder) - 1;
    if Result < 0 then
    begin
      Result := Length(AOrder) * 2;
    end;
    Exit;
  end;
  Result := Length(AOrder) * 2 + 1;
end;

class function TAtlasButtonBar.Order(const ARoles: TArray<TAtlasButtonRole>; const AOrder: string): TArray<Integer>;
var
  mOrder: TArray<string>;
  mIndex, mPos, mValue: Integer;
begin
  mOrder := AOrder.Split([',']);
  SetLength(Result, Length(ARoles));
  for mIndex := 0 to High(ARoles) do
  begin
    Result[mIndex] := mIndex;
  end;
  // Einfügen: stabil, gleiche Ränge behalten ihre Folge.
  for mIndex := 1 to High(Result) do
  begin
    mValue := Result[mIndex];
    mPos := mIndex - 1;
    while (mPos >= 0) and (Rank(ARoles[Result[mPos]], mOrder) > Rank(ARoles[mValue], mOrder)) do
    begin
      Result[mPos + 1] := Result[mPos];
      Dec(mPos);
    end;
    Result[mPos + 1] := mValue;
  end;
end;

class function TAtlasButtonBar.Layout(ACount: Integer; const ASize: TSize; APosition: TAtlasButtonBarPosition;
  const AClient: TRect; AMargin, AGap: Integer): TArray<TRect>;
var
  mIndex, mLeft, mTop, mWidth, mHeight: Integer;
begin
  mWidth := ASize.cx;
  mHeight := ASize.cy;
  SetLength(Result, ACount);
  for mIndex := 0 to ACount - 1 do
  begin
    case APosition of
      TAtlasButtonBarPosition.BottomLeft:
        begin
          mLeft := AClient.Left + AMargin + mIndex * (mWidth + AGap);
          mTop := AClient.Bottom - AMargin - mHeight;
        end;
      TAtlasButtonBarPosition.RightTop:
        begin
          mLeft := AClient.Right - AMargin - mWidth;
          mTop := AClient.Top + AMargin + mIndex * (mHeight + AGap);
        end;
      TAtlasButtonBarPosition.RightBottom:
        begin
          mLeft := AClient.Right - AMargin - mWidth;
          mTop := AClient.Bottom - AMargin - mHeight - (ACount - 1 - mIndex) * (mHeight + AGap);
        end;
    else
      mLeft := AClient.Right - AMargin - mWidth - (ACount - 1 - mIndex) * (mWidth + AGap);
      mTop := AClient.Bottom - AMargin - mHeight;
    end;
    Result[mIndex] := Rect(mLeft, mTop, mLeft + mWidth, mTop + mHeight);
  end;
end;

class function TAtlasButtonBar.AnchorsOf(APosition: TAtlasButtonBarPosition): TAtlasButtonAnchors;
begin
  case APosition of
    TAtlasButtonBarPosition.BottomLeft:
      Result := [TAtlasButtonAnchor.Left, TAtlasButtonAnchor.Bottom];
    TAtlasButtonBarPosition.RightTop:
      Result := [TAtlasButtonAnchor.Top, TAtlasButtonAnchor.Right];
  else
    Result := [TAtlasButtonAnchor.Right, TAtlasButtonAnchor.Bottom];
  end;
end;

class function TAtlasButtonBar.CommonHeight(const AHeights: TArray<Integer>): Integer;
var
  mIndex, mOther, mCount, mBest: Integer;
begin
  Result := 0;
  mBest := 0;
  for mIndex := 0 to High(AHeights) do
  begin
    mCount := 0;
    for mOther := 0 to High(AHeights) do
    begin
      if AHeights[mOther] = AHeights[mIndex] then
      begin
        Inc(mCount);
      end;
    end;
    if (AHeights[mIndex] > 0) and (mCount > mBest) then
    begin
      mBest := mCount;
      Result := AHeights[mIndex];
    end;
  end;
end;

class function TAtlasButtonBar.HandlerCloses(const ASource, AMethod: string): Boolean;
var
  mHead: TMatch;
  mBody: string;
  mEnd: TMatch;
begin
  Result := False;
  if (AMethod = '') or (ASource = '') then
  begin
    Exit;
  end;
  // Rumpf: vom Kopf „procedure TForm1.Methode“ bis zur nächsten Routine bzw. zum Ende der Unit.
  mHead := TRegEx.Match(ASource, '^\s*procedure\s+[\w.]+\.' + AMethod + '\b', [roIgnoreCase, roMultiLine]);
  if not mHead.Success then
  begin
    Exit;
  end;
  mBody := Copy(ASource, mHead.Index + mHead.Length, MaxInt);
  mEnd := TRegEx.Match(mBody, '^\s*(procedure|function|constructor|destructor|initialization|finalization|end\.)\b',
    [roIgnoreCase, roMultiLine]);
  if mEnd.Success then
  begin
    mBody := Copy(mBody, 1, mEnd.Index - 1);
  end;
  Result := TRegEx.IsMatch(mBody, '\bModalResult\s*:=', [roIgnoreCase]) or
    TRegEx.IsMatch(mBody, '\bClose\s*(;|\(|$|end\b)', [roIgnoreCase, roMultiLine]);
end;

end.
