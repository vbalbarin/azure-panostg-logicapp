# Creation of Palo Alto IP Address Object Groups through Serverless Automation

## Introduction

While Palo Alto Network firewall PANOS 8.+ supports a connection to Azure that enables automatic creation of dynamic ip address groups, limititations in the way it reads an Azure resource's attributes render it unsuited Yale University's environment. This solution takes advantage of the rich automation features of Azure to implement an automation pipeline triggered by the creation, modification, or deletion of an Azure Virtual machine and resulting in a configuration file that may be consumed by a PAN firewall device.

## Description of Solution

## Implementation of Solution

### Creation of runbook

### Creation of logic App

A service principal must be created for use by the Azure runbook and by the Logic App API connection object.

## Author

Vincent Balbarin <vincent.balbarin@yale.edu>

## License

The licenses of these documents are held by [@YaleUniversity](https://github.com/YaleUniversity) under [MIT License](/LICENSE.md).

## References