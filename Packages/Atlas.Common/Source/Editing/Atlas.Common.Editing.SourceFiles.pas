unit Atlas.Common.Editing.SourceFiles;

// Dateien dateiübergreifender Umbauten (Methode ohne Self, Typalias): Text, Syntaxbaum und die Stellen der
// Verwendungen je Datei.

interface

uses
  Atlas.Common.Pascal.SyntaxTree;

type
  /// <summary>Datei eines dateiübergreifenden Umbaus: Text, Baum und Anfang des Namens je Verwendung
  /// (0-basierte Offsets; ohne Deklaration und Kopf).</summary>
  TEditingSourceFile = record
    FileName: string;
    Text: string;
    Tree: TSyntaxTree;
    Offsets: TArray<Integer>;
    class function Create(const AFileName, AText: string; ATree: TSyntaxTree): TEditingSourceFile; overload;
      static;
    class function Create(const AFileName, AText: string; ATree: TSyntaxTree;
      const AOffsets: TArray<Integer>): TEditingSourceFile; overload; static;
  end;

implementation

{ TEditingSourceFile }

class function TEditingSourceFile.Create(const AFileName, AText: string; ATree: TSyntaxTree): TEditingSourceFile;
begin
  Result := Create(AFileName, AText, ATree, nil);
end;

class function TEditingSourceFile.Create(const AFileName, AText: string; ATree: TSyntaxTree;
  const AOffsets: TArray<Integer>): TEditingSourceFile;
begin
  Result.FileName := AFileName;
  Result.Text := AText;
  Result.Tree := ATree;
  Result.Offsets := AOffsets;
end;

end.
