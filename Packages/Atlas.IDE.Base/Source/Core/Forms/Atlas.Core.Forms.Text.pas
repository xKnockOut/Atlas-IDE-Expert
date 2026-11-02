unit Atlas.Core.Forms.Text;

// Formulartext aus dem Designer (#402), Teil ohne VCL und Open Tools API:
// Bei offenem Formular liegt der aktuelle Stand im Designer, nicht in der
// .dfm auf der Platte. Das Plugin streamt die Wurzelkomponente wie beim
// Speichern (TWriter.WriteDescendent ohne Vorfahr) und wandelt das Ergebnis
// mit ObjectBinaryToText in DFM-Text. Methodennamen von Ereignissen kennt im
// Designer nur der Designer; sie kommen über AMethodName.

interface

uses
  System.SysUtils,
  System.Classes;

type
  TAtlasFormText = class
  public
    /// <summary>DFM-Text zu ARoot. AMethodName liefert den Namen eines Ereignis-Handlers ('' = unbekannt);
    /// nil: Namen aus den published-Methoden der Wurzel.</summary>
    class function Write(ARoot: TComponent; const AMethodName: TFunc<TMethod, string>): string; static;
  end;

implementation

type
  TMethodNamer = class
  private
    FMethodName: TFunc<TMethod, string>;
  public
    procedure FindMethodName(Writer: TWriter; AMethod: TMethod; var AName: string);
  end;

procedure TMethodNamer.FindMethodName(Writer: TWriter; AMethod: TMethod; var AName: string);
begin
  if Assigned(FMethodName) then
    AName := FMethodName(AMethod);
end;

class function TAtlasFormText.Write(ARoot: TComponent; const AMethodName: TFunc<TMethod, string>): string;
var
  Binary: TMemoryStream;
  Text: TStringStream;
  Writer: TWriter;
  Namer: TMethodNamer;
begin
  Binary := TMemoryStream.Create;
  Text := TStringStream.Create('', TEncoding.UTF8);
  Namer := TMethodNamer.Create;
  try
    Namer.FMethodName := AMethodName;
    Writer := TWriter.Create(Binary, 4096);
    try
      if Assigned(AMethodName) then
        Writer.OnFindMethodName := Namer.FindMethodName;
      Writer.WriteDescendent(ARoot, nil);
    finally
      // Erst das Freigeben schreibt den Puffer in den Stream.
      Writer.Free;
    end;
    Binary.Position := 0;
    ObjectBinaryToText(Binary, Text);
    Result := Text.DataString;
  finally
    Namer.Free;
    Text.Free;
    Binary.Free;
  end;
end;

end.
