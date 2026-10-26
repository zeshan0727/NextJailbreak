FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

COPY src/NextAccountant.Core/NextAccountant.Core.csproj src/NextAccountant.Core/
COPY src/NextAccountant.Web/NextAccountant.Web.csproj src/NextAccountant.Web/
RUN dotnet restore src/NextAccountant.Web/NextAccountant.Web.csproj

COPY src ./src
RUN dotnet publish src/NextAccountant.Web/NextAccountant.Web.csproj -c Release -o /app/publish --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app
COPY --from=build /app/publish .
EXPOSE 8080
ENTRYPOINT ["dotnet", "NextAccountant.Web.dll"]
