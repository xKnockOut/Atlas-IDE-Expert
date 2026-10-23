unit Atlas.Common.Rationale.Contract;

// Contract des Features Begründungen (#1123): Kommentare, die erklären, warum
// Code so gebaut ist, etwa
//   // WHY: Delphi 12 kennt keinen if-Ausdruck.
//   // HACK: Umgeht QC 12345, bis der Fix in der RTL ist.
//   { RATIONALE: siehe ADR-0007 }
// Eine Begründung beginnt mit einer Marke (Vorgabe NOTE, WHY, HACK, IMPORTANT,
// RATIONALE; Einstellung hints.rationaleMarkers, Groß-/Kleinschreibung egal).
// Danach folgt ein Doppelpunkt; ohne Doppelpunkt zählt die Marke nur in
// Großbuchstaben ("// NOTE das …"), damit gewöhnliche Sätze keine Einträge
// werden. Wie Kommentare einer Deklaration zugeordnet werden, steht in
// Atlas.Common.Rationale.Scanner.
//
// Der Index speichert alle Kommentare mit einer möglichen Marke (Encode); erst
// die Anzeige filtert nach den eingestellten Marken (Filter). So wirkt eine
// neue Marke ohne neues Indizieren. TODO und FIXME gehören zur TODO-Übersicht
// (#68) und erscheinen hier nie, auch wenn sie in den Marken stehen.
//
// Verweise im Text (TRationaleLink) findet Atlas.Common.Rationale.References:
// ADR-0007 bzw. ADR 7 auf eine Architekturentscheidung im Ordner
// hints.adrFolder, #312 auf ein Issue, URLs.

interface

type
  /// <summary>Eine Begründung.</summary>
  TRationaleEntry = record
    /// <summary>Marke in Großbuchstaben, z. B. WHY.</summary>
    Marker: string;
    /// <summary>Text nach der Marke, Leerraum zusammengefasst, höchstens TRationale.MaxText Zeichen.</summary>
    Text: string;
    /// <summary>Zeile des Kommentars (0-basiert).</summary>
    Line: Integer;
    class function Create(const AMarker, AText: string; ALine: Integer): TRationaleEntry; static;
  end;

  {$SCOPEDENUMS ON}
  TRationaleLinkKind = (Adr, Issue, Url);
  {$SCOPEDENUMS OFF}

  /// <summary>Verweis im Text einer Begründung.</summary>
  TRationaleLink = record
    Kind: TRationaleLinkKind;
    /// <summary>Anfang im Text (0-basiert) und Länge des Verweises, z. B. "ADR-0007".</summary>
    Start: Integer;
    Length: Integer;
    /// <summary>Adr und Issue: Nummer ohne führende Nullen ("7", "312"); Url: die Adresse.</summary>
    Key: string;
  end;

  // Record statt Klasse: ein Contract enthält nur Werttypen und Interfaces (Konzept 7.1, Code-Review A-12).
  TRationale = record
  public const
    MaxText = 300;
    /// <summary>Höchstens so viele Einträge je Symbol bzw. Unit im Index.</summary>
    MaxEntries = 20;
    /// <summary>Ordner der Architekturentscheidungen, wenn hints.adrFolder fehlt.</summary>
    DefaultAdrFolder = 'docs/adr';
  public
    /// <summary>NOTE, WHY, HACK, IMPORTANT, RATIONALE.</summary>
    class function DefaultMarkers: TArray<string>; static;
    /// <summary>Steht AMarker in AMarkers (Groß-/Kleinschreibung egal)?</summary>
    class function HasMarker(const AMarkers: TArray<string>; const AMarker: string): Boolean; static;
    /// <summary>Einträge, deren Marke in AMarkers und nicht in AExcluded (TODO-Marken) steht, in Reihenfolge.
    /// </summary>
    class function Filter(const AEntries: TArray<TRationaleEntry>; const AMarkers,
      AExcluded: TArray<string>): TArray<TRationaleEntry>; static;
    /// <summary>Eintrag als eine Zeichenkette für den Index: Marke, Zeile und Text durch Tabulatoren getrennt.
    /// </summary>
    class function Encode(const AEntry: TRationaleEntry): string; static;
    class function TryDecode(const AValue: string; out AEntry: TRationaleEntry): Boolean; static;
    class function EncodeAll(const AEntries: TArray<TRationaleEntry>): TArray<string>; static;
    class function DecodeAll(const AValues: TArray<string>): TArray<TRationaleEntry>; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils;

{ TRationaleEntry }

class function TRationaleEntry.Create(const AMarker, AText: string; ALine: Integer): TRationaleEntry;
begin
  Result.Marker := AMarker;
  Result.Text := AText;
  Result.Line := ALine;
end;

{ TRationale }

class function TRationale.DefaultMarkers: TArray<string>;
begin
  Result := TArray<string>.Create('NOTE', 'WHY', 'HACK', 'IMPORTANT', 'RATIONALE');
end;

class function TRationale.HasMarker(const AMarkers: TArray<string>; const AMarker: string): Boolean;
var
  mMarker: string;
begin
  for mMarker in AMarkers do
    if SameText(Trim(mMarker), AMarker) then
      Exit(True);
  Result := False;
end;

class function TRationale.Filter(const AEntries: TArray<TRationaleEntry>; const AMarkers,
  AExcluded: TArray<string>): TArray<TRationaleEntry>;
var
  mEntry: TRationaleEntry;
begin
  Result := nil;
  for mEntry in AEntries do
    if HasMarker(AMarkers, mEntry.Marker) and not HasMarker(AExcluded, mEntry.Marker) then
      Result := Result + [mEntry];
end;

class function TRationale.Encode(const AEntry: TRationaleEntry): string;
begin
  Result := AEntry.Marker + #9 + IntToStr(AEntry.Line) + #9 + AEntry.Text;
end;

class function TRationale.TryDecode(const AValue: string; out AEntry: TRationaleEntry): Boolean;
var
  mFirst, mSecond, mLine: Integer;
begin
  AEntry := Default(TRationaleEntry);
  mFirst := Pos(#9, AValue);
  mSecond := PosEx(#9, AValue, mFirst + 1);
  Result := (mFirst > 1) and (mSecond > mFirst) and
    TryStrToInt(Copy(AValue, mFirst + 1, mSecond - mFirst - 1), mLine);
  if Result then
    AEntry := TRationaleEntry.Create(Copy(AValue, 1, mFirst - 1), Copy(AValue, mSecond + 1, MaxInt), mLine);
end;

class function TRationale.EncodeAll(const AEntries: TArray<TRationaleEntry>): TArray<string>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(AEntries));
  for mIndex := 0 to High(AEntries) do
    Result[mIndex] := Encode(AEntries[mIndex]);
end;

class function TRationale.DecodeAll(const AValues: TArray<string>): TArray<TRationaleEntry>;
var
  mValue: string;
  mEntry: TRationaleEntry;
begin
  Result := nil;
  for mValue in AValues do
    if TryDecode(mValue, mEntry) then
      Result := Result + [mEntry];
end;


end.
