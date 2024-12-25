
Clear-Host

$sourceFolderPath = Get-Location # текущая папка
# $sourceFolderPath = "C:\Файлы\Другое" # Можно указать конкретную папку

function Get-RoundedFileSize($fileSize){

    # Массив с различными единицами измерения
    $sizeUnits = @("Б", "КБ", "МБ", "ГБ", "ТБ")

    # Нахождение наиболее подходящей единицы измерения
    $sizeUnitIndex = 0
    while ($fileSize -ge 1024 -and $sizeUnitIndex -lt $sizeUnits.Length) {
        $fileSize /= 1024
        $sizeUnitIndex++
    }

    # Форматированный вывод размера с округлением до трех значащих цифр
    Write-Output ("{0:N3} {1}" -f $fileSize, $sizeUnits[$sizeUnitIndex])
}

# Функция для перемещения файла в корзину
function Move-ToRecycleBin {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    try {
        $shell = New-Object -ComObject Shell.Application
        $folder = $shell.NameSpace((Get-Item $Path).DirectoryName)
        $file = $folder.ParseName((Get-Item $Path).Name)

        # Удаляем в корзину
        $file.InvokeVerb("delete")
    } catch {
        Write-Error "Не удалось переместить файл в корзину"
    }
}

# Получаем все файлы в исходной папке
$files = Get-ChildItem -Path $sourceFolderPath -File

Write-Host "В папке '$($sourceFolderPath)' найдено файлов: $($files.Count)"

# Создаем массив для хранения информации о группах
$groups = @{}

# Группируем файлы по размеру. Оставляем только те группы, где больше одного файла
$sizeGroups = $files | Group-Object -Property Length | Where-Object { $_.Count -gt 1 }

$step = 0
$totalDeletedSize = 0
$totalDeletedCount = 0

# Обрабатываем каждую группу файлов с одинаковым размером
foreach ($sizeGroup in $sizeGroups) {

    $fileSize_string = Get-RoundedFileSize $sizeGroup.Group[0].Length
    $step++
    Write-Host
    Write-Host "[$($step)/$($sizeGroups.Count)] Файлы с размером $($fileSize_string): $($sizeGroup.Count) шт."
    

    # Создаем массив для хранения информации о группах с одинаковыми контрольными суммами
    $checksumGroups = @{}

    # Обрабатываем каждый файл внутри группы одинаковых размеров
    foreach ($file in $sizeGroup.Group) {

        # Получаем хеш содержимого файла
        $hash = Get-FileHash -Path $file.FullName -Algorithm MD5
            
        # Создаем массив для хранения файлов в группе, если она ещё не создана
        if (-not $checksumGroups.ContainsKey($hash.Hash)) {
            $checksumGroups[$hash.Hash] = @()
        }

        # Добавляем файл в соответствующую группу
        $checksumGroups[$hash.Hash] += $file
    }

    # Обрабатываем каждую группу файлов с одинаковыми контрольными суммами
    foreach ($checksumGroupKey in $checksumGroups.Keys) {
        
        $checksumGroup = $checksumGroups[$checksumGroupKey]
        if ($checksumGroup.Count -gt 1) {
                
            # Сортируем файлы в группе по длине названия в порядке возрастания, а затем по алфавиту
            $sortedFiles = $checksumGroup | Sort-Object -Property @{Expression = { $_.Name.Length }}, @{Expression = { $_.Name }}

            # Оставляем файл с самым коротким именем
            $keptFile = $sortedFiles | Select-Object -First 1
            Write-Host "        → Оставлен файл    '$($keptFile.Name)'"
            
            
            # Удаляем дубликаты
            $duplicates = $sortedFiles | Select-Object -Skip 1
            foreach ($duplicate in $duplicates) {
                
                $totalDeletedSize += $duplicate.Length
                $totalDeletedCount++

                Move-ToRecycleBin -Path $duplicate.FullName
                Write-Host "         × Удалён дубликат '$($duplicate.Name)'"
            }
        } else {
            Write-Host "        ★ Уникальный файл  '$($checksumGroup[0].Name)'"
        }
    }
}

Write-Host
Write-Host "Удалено файлов: $totalDeletedCount"
Write-Host "Суммарный размер удалённых файлов: $(Get-RoundedFileSize $totalDeletedSize)"
Write-Host "*** Процесс завершён. Нажмите Enter для выхода ***"
Read-Host
