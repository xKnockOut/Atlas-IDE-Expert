unit Atlas.Text.LogMarks;

// Kennzeichnung schutzwürdiger Werte in Protokollzeilen (#1478), gemeinsam
// für Server und Plugin.
//
// Wer eine Protokollzeile baut, weiß, welcher Teil ein Name, ein Pfad oder
// fremder Text ist; die Senke weiß es nicht mehr. Früher riet der
// Anonymisierer nachträglich aus dem fertigen Text (Pfadmuster, Text in
// Anführungszeichen, bekannte Namen), und alles, was er nicht erkannte,
// stand im Klartext im Log: Typ- und Routinennamen, Meldungen von
// Exceptions, Compilertexte. Deshalb kennzeichnet die Stelle, an der die
// Zeile entsteht, solche Werte:
// - Name: Projekt-, Unit-, Typ-, Routinen-, Formular-, Benutzer- oder
//   Rechnername.
// - Path: Datei- oder Ordnerpfad, Datei-URI, Dateiname.
// - Text: Text, dessen Inhalt Atlas nicht bestimmt (Meldung einer Exception,
//   Compilermeldung, Parameter einer Anfrage, Quelltext).
// Die Kennzeichen sind Zeichen aus dem privaten Bereich von Unicode
// (U+E000 Art Wert U+E001); sie stehen in keinem Quelltext und in keiner
// Meldung. Jede Senke entscheidet selbst: Plain entfernt sie (Klarnamen, z. B.
// Ausgabefenster der IDE), Resolve ersetzt jeden Wert über eine Funktion
// (anonymes Log: name#N, datei#N, text#N bzw. <name>, <pfad>, <text>).

interface

uses
  System.SysUtils;

type
{$SCOPEDENUMS ON}
  TLogMarkKind = (Name, Path, Text);
{$SCOPEDENUMS OFF}

  /// <summary>Ersatz für einen gekennzeichneten Wert.</summary>
  TLogMarkMap = reference to function(AKind: TLogMarkKind; const AValue: string): string;

  TLogMarks = record
  public const
    cStartChar = #$E000;
    cStopChar = #$E001;
    /// <summary>Art im Kennzeichen, in der Reihenfolge von TLogMarkKind.</summary>
    cKindChars: array[TLogMarkKind] of Char = ('N', 'P', 'T');
  public
    /// <summary>AValue als Name gekennzeichnet (Projekt, Unit, Typ, Routine, Benutzer …).</summary>
    class function Name(const AValue: string): string; static;
    /// <summary>AValue als Pfad gekennzeichnet (Datei, Ordner, Datei-URI, Dateiname).</summary>
    class function Path(const AValue: string): string; static;
    /// <summary>AValue als fremder Text gekennzeichnet (Meldung einer Exception, Compilertext, Quelltext).
    /// </summary>
    class function Text(const AValue: string): string; static;
    /// <summary>AValue mit der Art AKind gekennzeichnet; Kennzeichen in AValue fallen weg. Leerer Wert bleibt leer.
    /// </summary>
    class function Mark(AKind: TLogMarkKind; const AValue: string): string; static;
    /// <summary>Enthält AText ein Kennzeichen?</summary>
    class function HasMarks(const AText: string): Boolean; static;
    /// <summary>AText ohne Kennzeichen, die Werte im Klartext.</summary>
    class function Plain(const AText: string): string; static;
    /// <summary>Jeder gekennzeichnete Wert wird zu AMap(Art, Wert); der übrige Text bleibt. Ein Kennzeichen ohne
    /// Ende reicht bis zum Ende von AText.</summary>
    class function Resolve(const AText: string; const AMap: TLogMarkMap): string; static;
  end;

implementation

function KindOf(AChar: Char; out AKind: TLogMarkKind): Boolean;
var
  mKind: TLogMarkKind;
begin
  for mKind := Low(TLogMarkKind) to High(TLogMarkKind) do
  begin
    if TLogMarks.cKindChars[mKind] = AChar then
    begin
      AKind := mKind;
      Exit(True);
    end;
  end;
  AKind := TLogMarkKind.Text;
  Result := False;
end;

/// <summary>AValue ohne Kennzeichen-Zeichen.</summary>
function WithoutMarkChars(const AValue: string): string;
begin
  Result := AValue;
  if TLogMarks.HasMarks(Result) then
  begin
    Result := StringReplace(StringReplace(Result, TLogMarks.cStartChar, '', [rfReplaceAll]), TLogMarks.cStopChar, '',
      [rfReplaceAll]);
  end;
end;

class function TLogMarks.Mark(AKind: TLogMarkKind; const AValue: string): string;
begin
  if AValue = '' then
  begin
    Exit('');
  end;
  Result := cStartChar + cKindChars[AKind] + WithoutMarkChars(AValue) + cStopChar;
end;

class function TLogMarks.Name(const AValue: string): string;
begin
  Result := Mark(TLogMarkKind.Name, AValue);
end;

class function TLogMarks.Path(const AValue: string): string;
begin
  Result := Mark(TLogMarkKind.Path, AValue);
end;

class function TLogMarks.Text(const AValue: string): string;
begin
  Result := Mark(TLogMarkKind.Text, AValue);
end;

class function TLogMarks.HasMarks(const AText: string): Boolean;
begin
  Result := (Pos(cStartChar, AText) > 0) or (Pos(cStopChar, AText) > 0);
end;

/// <summary>Wert des Kennzeichens ab AStart (StartChar); AStart steht danach hinter dem Kennzeichen.</summary>
function ReadMark(const AText: string; var AStart: Integer; out AKind: TLogMarkKind): string;
var
  mStop, mFirst: Integer;
begin
  mFirst := AStart + 1;
  if (mFirst <= Length(AText)) and KindOf(AText[mFirst], AKind) then
  begin
    Inc(mFirst);
  end;
  mStop := mFirst;
  while (mStop <= Length(AText)) and (AText[mStop] <> TLogMarks.cStopChar) do
  begin
    Inc(mStop);
  end;
  Result := WithoutMarkChars(Copy(AText, mFirst, mStop - mFirst));
  AStart := mStop + 1;
end;

class function TLogMarks.Resolve(const AText: string; const AMap: TLogMarkMap): string;
var
  mBuilder: TStringBuilder;
  mIndex: Integer;
  mKind: TLogMarkKind;
  mValue: string;
begin
  if not HasMarks(AText) then
  begin
    Exit(AText);
  end;
  mBuilder := TStringBuilder.Create(Length(AText));
  try
    mIndex := 1;
    while mIndex <= Length(AText) do
    begin
      if AText[mIndex] = cStartChar then
      begin
        mValue := ReadMark(AText, mIndex, mKind);
        mBuilder.Append(AMap(mKind, mValue));
      end
      else
      begin
        // Ein einzelnes Endzeichen ohne Anfang fällt weg.
        if AText[mIndex] <> cStopChar then
        begin
          mBuilder.Append(AText[mIndex]);
        end;
        Inc(mIndex);
      end;
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

class function TLogMarks.Plain(const AText: string): string;
begin
  Result := Resolve(AText,
    function(AKind: TLogMarkKind; const AValue: string): string
    begin
      Result := AValue;
    end);
end;

end.
