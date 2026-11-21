unit Atlas.Text.Names;

// Namen in Delphi-Quelltext und Units zu Dateinamen (gemeinsam für Server und
// Plugin): letzter Teil eines qualifizierten Namens, Name mit Container,
// Unit-Name einer .pas-Datei, Quelltextdateien (.pas, .dpr, .dpk), Namen ohne
// Typparameter, &-Präfix oder T-Präfix, Namenslisten mit Kommas, Ordnerschlüssel
// und Pfade relativ zu einem Wurzelordner.

interface

type
  TTextNames = class
  public
    /// <summary>Teil hinter dem letzten Punkt ("Unit.TKlasse.Methode" → "Methode"); ohne Punkt AName.</summary>
    class function LastPart(const AName: string): string; static;
    /// <summary>"AContainer.AName"; ohne Container nur AName.</summary>
    class function Qualified(const AContainer, AName: string): string; static;
    /// <summary>Unit-Name einer .pas-Datei (Dateiname ohne Endung); '' für andere Dateien.</summary>
    class function UnitNameOf(const AFileName: string): string; static;
    /// <summary>Endet AFileName auf .pas, .dpr oder .dpk (ohne Rücksicht auf Groß-/Kleinschreibung)?</summary>
    class function IsPascalFile(const AFileName: string): Boolean; static;
    /// <summary>Teil vor dem letzten Punkt ("TKlasse.Methode" → "TKlasse"); ohne Punkt ''.</summary>
    class function ContainerOf(const AName: string): string; static;
    /// <summary>AName ohne vorangestelltes &amp; (&amp;Type → Type).</summary>
    class function WithoutAmpersand(const AName: string): string; static;
    /// <summary>AName ohne Typparameter und ohne Leerraum außen ("TList&lt;T&gt;" → "TList").</summary>
    class function WithoutGenerics(const AName: string): string; static;
    /// <summary>AName ohne Typparameter und ohne Container ("Unit.TList&lt;T&gt;" → "TList").</summary>
    class function BareTypeName(const AName: string): string; static;
    /// <summary>AName ohne das T der Typnamen-Konvention (TFoo → Foo); andere Namen unverändert.</summary>
    class function WithoutTypePrefix(const AName: string): string; static;
    /// <summary>AName mit großem Anfangsbuchstaben.</summary>
    class function Capitalized(const AName: string): string; static;
    /// <summary>Folgt der letzte Teil von AName der Konvention für Interfaces (IFoo)?</summary>
    class function LooksLikeInterface(const AName: string): Boolean; static;
    /// <summary>Wie CompareText; bei Gleichstand entscheidet CompareStr (eindeutige Reihenfolge).</summary>
    class function Compare(const ALeft, ARight: string): Integer; static;
    /// <summary>Namen der Liste "A, B,C" ohne Leerraum, leere ausgelassen.</summary>
    class function SplitList(const ANames: string): TArray<string>; static;
    /// <summary>Steht AName (ohne Groß-/Kleinschreibung) in der Liste "A, B,C"?</summary>
    class function InList(const ANames, AName: string): Boolean; static;
    /// <summary>"interface" oder "implementation".</summary>
    class function SectionKeyword(AInterface: Boolean): string; static;
    /// <summary>Gleich viele Typnamen und paarweise gleich ohne Leerraum und Groß-/Kleinschreibung
    /// (TList&lt;Integer&gt; = tlist&lt; integer &gt;)?</summary>
    class function SameTypes(const A, B: TArray<string>): Boolean; static;
    /// <summary>Schlüssel eines Ordners: klein, mit "\" und ohne Trenner am Ende.</summary>
    class function FolderKey(const AFolder: string): string; static;
    /// <summary>AFileName relativ zu ARoot, wenn es darunter liegt; sonst unverändert.</summary>
    class function RelativeTo(const ARoot, AFileName: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils;

{ TTextNames }

class function TTextNames.LastPart(const AName: string): string;
var
  mDot: Integer;
begin
  Result := AName;
  mDot := LastDelimiter('.', Result);
  if mDot > 0 then
  begin
    Result := Copy(Result, mDot + 1, MaxInt);
  end;
end;

class function TTextNames.Qualified(const AContainer, AName: string): string;
begin
  if AContainer = '' then
  begin
    Result := AName;
  end
  else
  begin
    Result := AContainer + '.' + AName;
  end;
end;

class function TTextNames.UnitNameOf(const AFileName: string): string;
begin
  Result := '';
  if SameText(ExtractFileExt(AFileName), '.pas') then
  begin
    // ExtractFileName trennt unter Windows nur an '\': Pfade mit '/' vorher angleichen.
    Result := ChangeFileExt(ExtractFileName(AFileName.Replace('/', PathDelim)), '');
  end;
end;

class function TTextNames.IsPascalFile(const AFileName: string): Boolean;
var
  mExtension: string;
begin
  mExtension := LowerCase(ExtractFileExt(AFileName));
  Result := (mExtension = '.pas') or (mExtension = '.dpr') or (mExtension = '.dpk');
end;

class function TTextNames.ContainerOf(const AName: string): string;
var
  mDot: Integer;
begin
  Result := '';
  mDot := LastDelimiter('.', AName);
  if mDot > 0 then
  begin
    Result := Copy(AName, 1, mDot - 1);
  end;
end;

class function TTextNames.WithoutAmpersand(const AName: string): string;
begin
  Result := AName;
  if StartsStr('&', Result) then
  begin
    Result := Copy(Result, 2, MaxInt);
  end;
end;

class function TTextNames.WithoutGenerics(const AName: string): string;
var
  mAngle: Integer;
begin
  Result := Trim(AName);
  mAngle := Pos('<', Result);
  if mAngle > 0 then
  begin
    Result := Trim(Copy(Result, 1, mAngle - 1));
  end;
end;

class function TTextNames.BareTypeName(const AName: string): string;
begin
  Result := LastPart(WithoutGenerics(AName));
end;

class function TTextNames.WithoutTypePrefix(const AName: string): string;
begin
  Result := AName;
  if (Length(Result) > 1) and CharInSet(Result[1], ['T', 't']) and CharInSet(Result[2], ['A'..'Z']) then
  begin
    Result := Copy(Result, 2, MaxInt);
  end;
end;

class function TTextNames.Capitalized(const AName: string): string;
begin
  Result := AName;
  if Result <> '' then
  begin
    Result := UpperCase(Result[1]) + Copy(Result, 2, MaxInt);
  end;
end;

class function TTextNames.LooksLikeInterface(const AName: string): Boolean;
var
  mName: string;
begin
  mName := LastPart(AName);
  Result := (Length(mName) > 1) and (mName[1] = 'I') and CharInSet(mName[2], ['A'..'Z']);
end;

class function TTextNames.Compare(const ALeft, ARight: string): Integer;
begin
  Result := CompareText(ALeft, ARight);
  if Result = 0 then
  begin
    Result := CompareStr(ALeft, ARight);
  end;
end;

class function TTextNames.SplitList(const ANames: string): TArray<string>;
var
  mName: string;
begin
  Result := nil;
  for mName in SplitString(ANames, ',') do
  begin
    if Trim(mName) <> '' then
    begin
      Result := Result + [Trim(mName)];
    end;
  end;
end;

class function TTextNames.InList(const ANames, AName: string): Boolean;
var
  mName: string;
begin
  for mName in SplitString(ANames, ',') do
  begin
    if SameText(Trim(mName), AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TTextNames.SameTypes(const A, B: TArray<string>): Boolean;
var
  mIndex: Integer;
begin
  Result := Length(A) = Length(B);
  if Result then
  begin
    for mIndex := 0 to High(A) do
    begin
      if not SameText(StringReplace(A[mIndex], ' ', '', [rfReplaceAll]),
        StringReplace(B[mIndex], ' ', '', [rfReplaceAll])) then
      begin
        Exit(False);
      end;
    end;
  end;
end;

class function TTextNames.SectionKeyword(AInterface: Boolean): string;
begin
  Result := 'implementation';
  if AInterface then
  begin
    Result := 'interface';
  end;
end;

class function TTextNames.FolderKey(const AFolder: string): string;
begin
  Result := LowerCase(StringReplace(AFolder, '/', '\', [rfReplaceAll]));
  while (Length(Result) > 1) and (Result[Length(Result)] = '\') do
  begin
    Delete(Result, Length(Result), 1);
  end;
end;

class function TTextNames.RelativeTo(const ARoot, AFileName: string): string;
begin
  Result := AFileName;
  if (ARoot <> '') and StartsText(IncludeTrailingPathDelimiter(ARoot), AFileName) then
  begin
    Result := Copy(AFileName, Length(IncludeTrailingPathDelimiter(ARoot)) + 1, MaxInt);
  end;
end;

end.
